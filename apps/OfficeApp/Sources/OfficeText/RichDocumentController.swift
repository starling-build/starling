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

import Flutter
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
// (Indirect: its payloads are boxed. Two paragraph styles inline made a
// case of over a thousand scalars, and wasm32's outlined copy of it took
// each as a parameter — 1296, past V8's limit of 1000, so Chrome would not
// compile the Office app at all.)
/// The footnotes and endnotes as the editor holds them: the paragraphs the layout sets, and the file's parts that carry
/// them back on a save.
public struct NotesState: Equatable, Sendable {
    public var footnotes: [Int: [RichParagraph]]
    public var endnotes: [Int: [RichParagraph]]
    public var footnotePart: Data?
    public var endnotePart: Data?
    public init(_ doc: RichDocument) {
        footnotes = doc.footnotes; endnotes = doc.endnotes
        footnotePart = doc.keptParts["word/footnotes.xml"]; endnotePart = doc.keptParts["word/endnotes.xml"]
    }
    func put(into doc: inout RichDocument) {
        doc.footnotes = footnotes; doc.endnotes = endnotes
        doc.keptParts["word/footnotes.xml"] = footnotePart
        doc.keptParts["word/endnotes.xml"] = endnotePart
    }
}

/// The document-property parts (docProps/*) with their content types and package links: what File > Info edits.
public struct PropertyParts: Equatable, Sendable {
    public var parts: [String: Data]
    public var types: [String: String]
    public var rels: [KeptRel]
    public init(_ doc: RichDocument) {
        parts = doc.keptParts.filter { $0.key.hasPrefix("docProps/") }
        types = doc.keptPartTypes.filter { $0.key.hasPrefix("docProps/") }
        rels = doc.keptRootRels.filter { $0.target.hasPrefix("docProps/") }
    }
    func put(into doc: inout RichDocument) {
        for k in doc.keptParts.keys where k.hasPrefix("docProps/") { doc.keptParts[k] = nil }
        for k in doc.keptPartTypes.keys where k.hasPrefix("docProps/") { doc.keptPartTypes[k] = nil }
        doc.keptRootRels.removeAll { $0.target.hasPrefix("docProps/") }
        for (k, v) in parts { doc.keptParts[k] = v }
        for (k, v) in types { doc.keptPartTypes[k] = v }
        doc.keptRootRels += rels
    }
}

public indirect enum EditOp: Equatable, Sendable {
    case setProperties(new: PropertyParts, old: PropertyParts)
    case insertText(RichPosition, String, [Run])
    case deleteText(RichPosition, String, [Run])
    /// Restore exact bookmark boundaries as well as text when undoing an edit.
    case restoreParagraphs(Int, count: Int, [RichParagraph])
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
    /// The formatted default header or footer (W-HF-1), with the plain texts the strip and the kept-part check read.
    case setRichHeaderFooter(new: [RichHeaderFooter], old: [RichHeaderFooter], header: String, footer: String, oldHeader: String, oldFooter: String)
    /// The notes' text and their kept parts (W-FN-1): one step whatever it changes.
    case setNotes(new: NotesState, old: NotesState)
    /// A section's page (size, margins, columns): the paragraph that ends it, or -1 for the last section.
    case setSectionPage(Int, old: PageSetup?, new: PageSetup?)
    /// The document-level page options (the last section's different first page and first page number, odd/even headers).
    case setPageOptions(old: RichDocumentController.PageOptions, new: RichDocumentController.PageOptions)
    /// The last section's own header and footer references (W-HF-2 Link to Previous).
    case setKeptHeaderFooters(old: [KeptHeaderFooter], new: [KeptHeaderFooter])
    /// The last section's `w:type` (how it starts), as the file writes it.
    case setLastSectionType(old: String?, new: String?)
    /// A picture's shown size (its attachment replaced; the id survives).
    case setImage(Int, old: ImageAttachment, new: ImageAttachment)
    /// An inline picture in a paragraph's text, replaced (its id survives).
    case setInlineImage(Int, id: String, old: ImageAttachment, new: ImageAttachment)
    /// A table's column widths in points (nil: equal columns).
    case setTableColumns(String, old: [Double]?, new: [Double]?)
    /// One entry of the style sheet, replaced (every paragraph re-lays out).
    case setStyleEntry(old: RichNamedStyle, new: RichNamedStyle)
    case addStyle(RichNamedStyle)
    case removeStyle(RichNamedStyle)
    /// A table's look (nil: the default).
    case setTableStyle(String, old: TableStyle?, new: TableStyle?)
    /// One level's format of one list (nil: the level's default).
    case setListFormat(String, level: Int, old: ListLevelFormat?, new: ListLevelFormat?)
    /// The number a list's level restarts at, the first time it is used (nil: none).
    case setListRestart(String, level: Int, old: Int?, new: Int?)
    case setListCounter(String, old: String?, new: String?)

    /// Apply to `doc`, appending the invalidation to `changes`, and return
    /// the inverse.
    @discardableResult
    func apply(to doc: inout RichDocument, changes: inout [RichChange]) -> EditOp {
        switch self {
        case .insertText(let pos, let text, let runs):
            let before = doc.paragraphs[pos.paragraph]
            doc.paragraphs[pos.paragraph].insert(text, at: pos.offset, runs: runs)
            changes.append(.changed(pos.paragraph))
            if before.hasMarkers { return .restoreParagraphs(pos.paragraph, count: 1, [before]) }
            return .deleteText(pos, text, runs)
        case .deleteText(let pos, let text, let runs):
            let before = doc.paragraphs[pos.paragraph]
            let units = text.utf16.count
            let removed = doc.paragraphs[pos.paragraph].delete(pos.offset ..< pos.offset + units)
            changes.append(.changed(pos.paragraph))
            if before.hasMarkers { return .restoreParagraphs(pos.paragraph, count: 1, [before]) }
            // Prefer what was actually removed (defensive: identical unless a
            // caller composed ops by hand).
            return .insertText(pos, removed.text.isEmpty ? text : removed.text,
                               removed.runs.isEmpty ? runs : removed.runs)
        case .restoreParagraphs(let index, let count, let paragraphs):
            let before = Array(doc.paragraphs[index ..< index + count])
            doc.paragraphs.replaceSubrange(index ..< index + count, with: paragraphs)
            changes.append(.changed(index))
            if count > 1 { changes.append(.removed(at: index + 1, count: count - 1)) }
            if paragraphs.count > 1 { changes.append(.inserted(at: index + 1, count: paragraphs.count - 1)) }
            return .restoreParagraphs(index, count: paragraphs.count, before)
        case .splitParagraph(let pos, let tailStyle):
            let before = doc.paragraphs[pos.paragraph]
            var tail = doc.paragraphs[pos.paragraph].split(at: pos.offset)
            let removedStyle = tail.style
            tail.style = tailStyle
            doc.paragraphs.insert(tail, at: pos.paragraph + 1)
            changes.append(.changed(pos.paragraph))
            changes.append(.inserted(at: pos.paragraph + 1, count: 1))
            _ = removedStyle
            if before.hasMarkers { return .restoreParagraphs(pos.paragraph, count: 2, [before]) }
            return .mergeParagraph(pos.paragraph, removedStyle: tailStyle)
        case .mergeParagraph(let index, let removedStyle):
            let head = doc.paragraphs[index]
            let headLength = doc.paragraphs[index].length
            let tail = doc.paragraphs.remove(at: index + 1)
            doc.paragraphs[index].append(tail)
            changes.append(.changed(index))
            changes.append(.removed(at: index + 1, count: 1))
            _ = removedStyle
            if head.hasMarkers || tail.hasMarkers {
                return .restoreParagraphs(index, count: 1, [head, tail])
            }
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
        case .setRichHeaderFooter(let new, let old, let header, let footer, let oldHeader, let oldFooter):
            doc.headerFooters = new
            doc.header = header
            doc.footer = footer
            changes.append(.all)
            return .setRichHeaderFooter(new: old, old: new, header: oldHeader, footer: oldFooter, oldHeader: header, oldFooter: footer)
        case .setProperties(let new, let old):
            new.put(into: &doc)
            return .setProperties(new: old, old: new)
        case .setNotes(let new, let old):
            new.put(into: &doc)
            changes.append(.all)
            return .setNotes(new: old, old: new)
        case .setSectionPage(let index, let old, let new):
            if index < 0 { doc.lastSectionPage = new } else { doc.paragraphs[index].style.sectionPage = new }
            changes.append(.all)
            return .setSectionPage(index, old: new, new: old)
        case .setPageOptions(let old, let new):
            doc.titlePage = new.titlePage; doc.evenAndOddHeaders = new.evenAndOdd; doc.pageNumberStart = new.pageNumberStart
            doc.pageNumberFormat = new.pageNumberFormat; doc.chapterStyle = new.chapterStyle; doc.chapterSeparator = new.chapterSeparator
            changes.append(.all)
            return .setPageOptions(old: new, new: old)
        case .setKeptHeaderFooters(let old, let new):
            doc.keptHeaderFooters = new
            changes.append(.all)
            return .setKeptHeaderFooters(old: new, new: old)
        case .setLastSectionType(let old, let new):
            doc.sectionTypeXML = new
            changes.append(.all)
            return .setLastSectionType(old: new, new: old)
        case .setImage(let index, let old, let new):
            doc.paragraphs[index].image = new
            changes.append(.changed(index))
            return .setImage(index, old: new, new: old)
        case .setInlineImage(let index, let id, let old, let new):
            doc.paragraphs[index].inlineImages[id] = new
            changes.append(.changed(index))
            return .setInlineImage(index, id: id, old: new, new: old)
        case .setTableColumns(let table, let old, let new):
            doc.tableColumns[table] = new
            for i in doc.paragraphs.indices where doc.paragraphs[i].cell?.table == table { changes.append(.changed(i)) }
            return .setTableColumns(table, old: new, new: old)
        case .setStyleEntry(let old, let new):
            doc.styles[new.id] = new
            changes.append(.all)
            return .setStyleEntry(old: new, new: old)
        case .addStyle(let e):
            doc.styles[e.id] = e
            changes.append(.all)
            return .removeStyle(e)
        case .removeStyle(let e):
            doc.styles[e.id] = nil
            changes.append(.all)
            return .addStyle(e)
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
        case .setListRestart(let id, let level, let old, let new):
            var restarts = doc.listRestarts[id] ?? [:]
            restarts[level] = new
            doc.listRestarts[id] = restarts.isEmpty ? nil : restarts
            for i in doc.paragraphs.indices where doc.paragraphs[i].style.listId == id { changes.append(.changed(i)) }
            changes.append(.lists)
            return .setListRestart(id, level: level, old: new, new: old)
        case .setListCounter(let id, let old, let new):
            doc.listCounterOf[id] = new
            for i in doc.paragraphs.indices where doc.paragraphs[i].style.listId == id { changes.append(.changed(i)) }
            changes.append(.lists)
            return .setListCounter(id, old: new, new: old)
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
    /// What the step was, in a word, for "Undo Typing".
    var label = ""
}

// MARK: - Controller

/// Owns a `RichDocument`, its selection, and the undo history.
public final class RichDocumentController: ChangeNotifier {
    private let _leakProbe = LeakProbe("RichDocumentController")
    public private(set) var document: RichDocument

    /// Add a part the file carries as is (a picture file a box names). Outside undo: a part nothing names is not saved.
    func _keepPart(_ name: String, _ data: Data) { document.keptParts[name] = data }

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
                // Shapes picked along with the selected one (Shift-click) last only while a picture stays selected.
                if !shapePicks.isEmpty, selectedImageIndex == nil { shapePicks = [] }
                if groupChild != nil { groupChild = nil }
                // A caret move breaks the typing run and drops the pending
                // style: Word does exactly this.
                if !_inEdit {
                    _breakCoalescing()
                    typingStyle = nil
                    _announceCellIfChanged()
                }
                notifyListeners()
            }
        }
    }

    private var _announcedCell: String?
    /// What a screen reader hears when the caret enters a table cell: "Row 2, column 3, Price" (the header row's
    /// text for that column), then nothing more until the caret leaves for another cell.
    public var cellDescription: String? {
        guard let c = currentCell else { return nil }
        var s = "Row \(c.row + 1), column \(c.column + 1)"
        if c.row > 0, tableLook(of: c.table) & 0x20 != 0, let h = document.paragraphs(inTable: c.table).first(where: {
            let r = document.paragraphs[$0].cell
            return r?.row == 0 && r?.column == c.column
        }) {
            let t = document.paragraphs[h].text
            if !t.isEmpty { s += ", " + t }
        }
        return s
    }

    private func _announceCellIfChanged() {
        guard ScreenReader.isListening, selection.focus.paragraph < document.paragraphs.count else { return }
        let cell = currentCell
        let key = cell.map { "\($0.table)/\($0.row)/\($0.column)" }
        if key == _announcedCell { return }
        _announcedCell = key
        if let d = cellDescription { ScreenReader.announce(d) }
    }

    /// The style the next typed character takes at a collapsed caret after
    /// a toggle (Ctrl+B with nothing selected). Cleared by any caret move.
    public var typingStyle: CharStyle?

    /// The last rich fragment copied from THIS controller, so an in-app paste
    /// keeps its formatting while the system clipboard only carries text.
    public private(set) var copiedFragment: [RichParagraph]?

    /// Editing is refused when set (a viewer, a locked document).
    /// Whether dragging a picture's handles, and its Width and Height boxes, keep the picture's proportions. On by
    /// default (Word's); off, a corner or an edge stretches it freely. A view setting: it is not saved in the file.
    public var pictureAspectLock = true
    public var readOnly = false

    /// A shape picked from Insert > Shapes that waits for the user to click or drag on the page: given the corner
    /// (points from the page's top left) and the size, it makes the picture to put there.
    /// The ids of the floating shapes picked in addition to the selected one (Shift-click), to be grouped with it.
    public internal(set) var shapePicks: [String] = []
    /// The child picked inside the selected group (click on the selected group, then on the child): its place among the group's shapes.
    public internal(set) var groupChild: Int?

    /// A finger has no Shift: while this is on, a tap on a floating shape adds it to the picked ones (or takes it out), as a
    /// Shift-click does. Dragging on an unselected shape still scrolls on touch.
    public private(set) var selectMultiple = false
    public func setSelectMultiple(_ on: Bool) {
        guard on != selectMultiple else { return }
        selectMultiple = on
        notifyListeners()
    }

    public var pendingShape: ((_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> ImageAttachment?)? = nil

    /// Put the pending shape (if any) at that corner and size on the page, select it, and stop waiting.
    @discardableResult
    public func placePendingShape(x: Double, y: Double, width: Double, height: Double, at position: RichPosition) -> Bool {
        guard let make = pendingShape else { return false }
        pendingShape = nil
        guard let shape = make(x, y, width, height) else { return false }
        _setCaret(position)
        insertImage(shape)
        if let i = document.paragraphs.firstIndex(where: { $0.image?.id == shape.id }) { selectImage(at: i) }
        return true
    }

    /// The results of the fields whose code is shown (see `toggleFieldCodes`), by field-code id.
    var _codeStash: [Int: [(text: String, style: CharStyle)]] = [:]
    var _codeNext = 1
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

    /// The last paste, while nothing else has changed the document since: what the Paste Options button
    /// offers to redo another way (see RichDocumentController+PasteOptions.swift).
    var _lastPaste: PasteRecord?

    deinit { LeakProbe.unregister(controller: self) }

    public init(document: RichDocument = RichDocument()) {
        self.document = document
        self.selection = RichSelection(caret: .start)
        super.init()
        LeakProbe.register(controller: self)
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
        var any = false
        for run in document.fragment(selection).flatMap(\.runs) where run.length > 0 {
            if !predicate(run.style) { return false }
            any = true
        }
        // A selection of no characters — a paragraph mark alone, from
        // the end of one paragraph to the start of the next — is not
        // bold and italic and struck through because nothing in it says
        // otherwise: it is as the text before the mark is.
        if !any {
            let p = document.clamped(selection.start)
            return predicate(document.paragraphs[p.paragraph].style(at: p.offset))
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
                let label: String
                switch undoKind {
                case .typing: label = "Typing"
                case .deleting: label = "Deleting"
                case .styleEdit: label = "Formatting"
                case .other: label = "Edit"
                }
                _undo.append(UndoEntry(inverses: [], selectionBefore: selection,
                                       selectionAfter: selection, kind: undoKind,
                                       continuation: nil, label: label))
                if _undo.count > maxUndoDepth { _undo.removeFirst(_undo.count - maxUndoDepth) }
            }
        }
        let boundBefore: [Int: String] = outer ? [:] : _customBoundTexts()
        let noteMarks = outer ? nil : _noteMarkIds()
        body()
        if !outer {
            _syncCustomBound(before: boundBefore)
            _dropOrphanNotes(before: noteMarks)
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

    // MARK: Content control locks

    /// Whether an edit at the selection touches a locked content control: its contents (a group control's, or a
    /// `contentLocked` one's) typed into or deleted, or a `sdtLocked` control deleted whole. Edits then do nothing, as in Word.
    func _selectionLocked() -> Bool {
        let a = document.clamped(selection.start), b = document.clamped(selection.end)
        let collapsed = selection.isCollapsed
        // Block-level controls: the paragraphs from the one that starts the control to the one that ends it.
        var open: [Int: (Int, RichControlLock)] = [:]
        for i in 0 ... b.paragraph {
            let p = document.paragraphs[i]
            for c in p.blockControlsBefore where c.isStart { open[c.id] = (i, RichControlLock(properties: c.properties)) }
            for c in p.blockControlsAfter where !c.isStart {
                guard let (first, lock) = open.removeValue(forKey: c.id), lock.isAny, i >= a.paragraph else { continue }
                let covers = a.paragraph <= first && b.paragraph >= i && !collapsed
                if lock.contents && !(covers && !lock.control) { return true }
                if lock.control && covers { return true }
            }
        }
        // Controls over runs.
        for i in a.paragraph ... b.paragraph {
            let p = document.paragraphs[i]
            guard !p.controlMarkers.isEmpty else { continue }
            let from = i == a.paragraph ? a.offset : 0
            let to = i == b.paragraph ? b.offset : p.length
            for m in p.controlMarkers where m.isStart {
                let lock = RichControlLock(properties: m.properties)
                guard lock.isAny, let end = p.controlMarkers.first(where: { $0.id == m.id && !$0.isStart }) else { continue }
                let lo = m.offset, hi = max(m.offset, end.offset)
                if collapsed {
                    if lock.contents && lo < from && from < hi { return true }
                } else {
                    let covers = from <= lo && to >= hi
                    if lock.contents && from < hi && to > lo && !(covers && !lock.control) { return true }
                    if lock.control && covers { return true }
                }
            }
        }
        return false
    }

    /// Text of every control bound to custom XML, by control id (empty when the document has no custom XML part).
    private func _customBoundTexts() -> [Int: String] {
        guard document.keptParts.keys.contains(where: { $0.hasPrefix("customXml/item") }) else { return [:] }
        var out: [Int: String] = [:]
        for p in document.paragraphs { for c in p.customBoundControls { out[c.id] = c.text } }
        return out
    }

    /// A control bound to custom XML that the edit changed sets its element; every other control on that element then
    /// shows the same text (inside the same undo step). The save writes the element back to the XML part.
    private func _syncCustomBound(before: [Int: String]) {
        guard !before.isEmpty else { return }
        var changed: (store: String, xpath: String, text: String)?
        var all: [(index: Int, id: Int, store: String, xpath: String, text: String)] = []
        for (i, p) in document.paragraphs.enumerated() {
            for c in p.customBoundControls {
                all.append((i, c.id, c.store, c.xpath, c.text))
                if changed == nil, let was = before[c.id], was != c.text { changed = (c.store, c.xpath, c.text) }
            }
        }
        guard let src = changed else { return }
        for c in all where c.store == src.store && c.xpath == src.xpath && c.text != src.text {
            if let after = document.paragraphs[c.index].settingControlText(c.id, to: src.text) {
                perform(.restoreParagraphs(c.index, count: 1, [after]))
            }
        }
    }

    /// End a run of coalesced edits: the next one starts a new undo step.
    /// A Modify Style strip calls this on Done, as typing does on a click.
    public func breakUndoCoalescing() { _breakCoalescing() }

    /// Apply one op inside an `edit` block.
    public func perform(_ op: EditOp) {
        precondition(_inEdit, "perform(_:) must run inside edit { }")
        let op = document.trackRevisions ? _trackingFormat(op) : op
        let inverse = op.apply(to: &document, changes: &_pendingChanges)
        _undo[_undo.count - 1].inverses.append(inverse)
    }

    private func _breakCoalescing() {
        if !_undo.isEmpty { _undo[_undo.count - 1].continuation = nil }
    }

    // MARK: Undo / redo

    /// Told what undo and redo did ("Undo Typing", "Nothing to redo"); the app hands it to a screen reader.
    public var onHistory: ((String) -> Void)?

    public func undo() {
        guard !readOnly else { return }
        guard let entry = _undo.popLast() else { onHistory?("Nothing to undo"); return }
        onHistory?("Undo \(entry.label)")
        var redoInverses: [EditOp] = []
        for op in entry.inverses.reversed() {
            redoInverses.append(op.apply(to: &document, changes: &_pendingChanges))
        }
        _redo.append(UndoEntry(inverses: redoInverses.reversed(),
                               selectionBefore: entry.selectionBefore,
                               selectionAfter: entry.selectionAfter,
                               kind: .other, continuation: nil, label: entry.label))
        typingStyle = nil
        revision += 1
        _inEdit = true
        selection = entry.selectionBefore
        _inEdit = false
        notifyListeners()
    }

    public func redo() {
        guard !readOnly else { return }
        guard let entry = _redo.popLast() else { onHistory?("Nothing to redo"); return }
        onHistory?("Redo \(entry.label)")
        // entry.inverses undo the undo, i.e. they re-apply the original edit.
        var undoInverses: [EditOp] = []
        for op in entry.inverses {
            undoInverses.append(op.apply(to: &document, changes: &_pendingChanges))
        }
        _undo.append(UndoEntry(inverses: undoInverses,
                               selectionBefore: entry.selectionBefore,
                               selectionAfter: entry.selectionAfter,
                               kind: .other, continuation: nil, label: entry.label))
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
    /// Insert a symbol, in `font` when given (one undo step); the typing style is left as it was.
    public func insertSymbol(_ string: String, font: String?) {
        guard !_selectionLocked() else { return }
        let saved = typingStyle
        if let font {
            var st = currentCharStyle
            st.fontFamily = font
            typingStyle = st
        }
        insertText(string)
        typingStyle = font == nil ? saved : nil
    }

    public func insertText(_ string: String) {
        guard !_selectionLocked() else { return }
        guard !string.isEmpty else { return }
        let hint: UndoKindHint = string.contains(Character("\n")) ? .other : .typing
        edit(kind: hint) {
            if hasSelection { _deleteSelectionOps() }
            if document.paragraphs[selection.focus.paragraph].isImage {
                // Typing on a picture starts a paragraph below it.
                let i = selection.focus.paragraph
                var added = RichParagraph()
                added.style.markRevision = _insertionMark()
                perform(.insertParagraphs(at: i + 1, [added]))
                _setCaret(RichPosition(paragraph: i + 1, offset: 0))
            }
            let style = typingStyle
            let pieces = string.split(separator: "\n", omittingEmptySubsequences: false)
            for (i, piece) in pieces.enumerated() {
                if i > 0 { _splitAtCaret() }
                let text = String(piece)
                if !text.isEmpty {
                    let pos = selection.focus
                    let runs = style.map { [Run(length: text.utf16.count, style: _typed(_leavingField($0, at: pos)))] }
                    let inherited = _typed(_leavingField(document.paragraphs[pos.paragraph].style(at: pos.offset), at: pos))
                    perform(.insertText(pos, text, runs ?? [Run(length: text.utf16.count, style: inherited)]))
                    _setCaret(RichPosition(paragraph: pos.paragraph, offset: pos.offset + text.utf16.count))
                }
            }
            typingStyle = style  // a typed run keeps the pending style alive
        }
    }

    /// Who is editing and when, for the tracked changes the editor records: the app sets it to the user's
    /// name and the clock (W3CDTF, as Word writes `w:date`).
    public nonisolated(unsafe) static var reviewer: () -> (author: String, date: String) = { ("", "") }

    /// The style of text the editor puts in: new text is never struck out, and with track changes on it is
    /// an insertion by the reviewer, as Word records typing (`w:ins` with author and date).
    func _typed(_ style: CharStyle) -> CharStyle {
        var out = style
        if out.revision?.kind == .deleted { out.revision = nil }
        if let mark = _insertionMark() { out.revision = mark }
        return out
    }

    /// An insertion by the reviewer, now; nil with track changes off.
    func _insertionMark() -> RevisionMark? {
        guard document.trackRevisions else { return nil }
        let who = Self.reviewer()
        return RevisionMark(kind: .inserted, author: who.author, date: who.date)
    }

    /// Text typed at the end of a field's result (or after it) is not part of the field: the field marks are dropped
    /// from the style it would inherit. Inside the result, typing stays in it.
    func _leavingField(_ style: CharStyle, at pos: RichPosition) -> CharStyle {
        guard style.fieldResult != 0 || style.preservedField != nil else { return style }
        let p = document.paragraphs[pos.paragraph]
        if pos.offset < p.text.utf16.count, p.style(at: pos.offset + 1).fieldResult == style.fieldResult { return style }
        var out = style
        out.preservedField = nil
        out.fieldResult = 0
        out.preservedFieldProperties = [:]
        return out
    }

    /// Enter: split the paragraph at the caret. A heading's continuation is
    /// body text, as in every word processor.
    public func insertParagraphBreak() {
        guard !_selectionLocked() else { return }
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
            var added = RichParagraph()
            added.style.markRevision = _insertionMark()
            perform(.insertParagraphs(at: pos.paragraph + 1, [added]))
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
        // With track changes on, the new mark is the one ending the text before the caret (Word marks that
        // pilcrow inserted; the paragraph's own mark, and any change to it, goes on with the text after).
        if let mark = _insertionMark() {
            let head = document.paragraphs[pos.paragraph].style
            var marked = head; marked.markRevision = mark
            perform(.setParagraphStyle(pos.paragraph, old: head, new: marked))
        }
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
        guard !_selectionLocked() else { return (false, false) }
        guard !fragment.isEmpty else { return (false, false) }
        var applied = (before: false, after: false)
        edit {
            if hasSelection { _deleteSelectionOps() }
            if document.paragraphs[selection.focus.paragraph].isImage {
                // Pasting or dropping on a picture goes below it, as typing does.
                let i = selection.focus.paragraph
                var added = RichParagraph()
                added.style.markRevision = _insertionMark()
                perform(.insertParagraphs(at: i + 1, [added]))
                _setCaret(RichPosition(paragraph: i + 1, offset: 0))
            }
            var fragment = fragment
            let mark = _insertionMark()
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
                    if let mark {  // tracked: the mark ending the text before the split is a new one
                        let head = document.paragraphs[pos.paragraph].style
                        var marked = head; marked.markRevision = mark
                        perform(.setParagraphStyle(pos.paragraph, old: head, new: marked))
                    }
                    pos = RichPosition(paragraph: pos.paragraph + 1, offset: 0)
                    // A fragment's inner paragraphs carry their own style.
                    let old = document.paragraphs[pos.paragraph].style
                    if old != para.style {
                        perform(.setParagraphStyle(pos.paragraph, old: old, new: para.style))
                    }
                }
                if !para.text.isEmpty {
                    let runs = mark == nil ? para.runs : para.runs.map { r in var r = r; r.style.revision = mark; return r }
                    perform(.insertText(pos, para.text, runs))
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
        guard !_selectionLocked() else { return }
        edit(kind: hasSelection ? .other : .deleting) {
            if hasSelection {
                _deleteSelectionOps()
                return
            }
            _backspaceOps(word: false)
        }
    }

    public func deleteForward() {
        guard !_selectionLocked() else { return }
        edit {
            if hasSelection {
                _deleteSelectionOps()
                return
            }
            _deleteForwardOps(word: false)
        }
    }

    public func deleteWordBackward() {
        guard !_selectionLocked() else { return }
        edit {
            if hasSelection {
                _deleteSelectionOps()
                return
            }
            _backspaceOps(word: true)
        }
    }

    public func deleteWordForward() {
        guard !_selectionLocked() else { return }
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

    /// The picture set in a line of text that the selection is exactly on (one U+FFFC character), with the character's
    /// offset in its paragraph.
    public var selectedInlineImage: (paragraph: Int, offset: Int, id: String)? {
        let a = selection.anchor, f = selection.focus
        guard a.paragraph == f.paragraph, abs(a.offset - f.offset) == 1, a.paragraph < document.paragraphs.count else { return nil }
        let p = document.paragraphs[a.paragraph]
        let at = min(a.offset, f.offset)
        guard let id = p.style(at: at + 1).inlineImage, p.inlineImages[id] != nil else { return nil }
        return (a.paragraph, at, id)
    }

    /// The pictures set in paragraph `index`'s text, in text order, each with its character's offset.
    public func inlineImageOffsets(in index: Int) -> [(offset: Int, id: String)] {
        guard index < document.paragraphs.count else { return [] }
        let p = document.paragraphs[index]
        var out: [(Int, String)] = []
        var pos = 0
        for run in p.runs {
            if let id = run.style.inlineImage, p.inlineImages[id] != nil { out.append((pos, id)) }
            pos += run.length
        }
        return out
    }

    /// Select the picture `id` set in paragraph `index`'s text (its one character).
    public func selectInlineImage(in index: Int, id: String) {
        guard let hit = inlineImageOffsets(in: index).first(where: { $0.id == id }) else { return }
        selection = RichSelection(anchor: RichPosition(paragraph: index, offset: hit.offset),
                                  focus: RichPosition(paragraph: index, offset: hit.offset + 1))
    }

    /// Show the inline picture `id` of paragraph `index` at `width` × `height` points, one undo step.
    public func setInlineImageSize(in index: Int, id: String, width: Double, height: Double) {
        guard index < document.paragraphs.count, let old = document.paragraphs[index].inlineImages[id] else { return }
        let w = max(4, width), h = max(4, height)
        guard abs(w - old.width) > 0.01 || abs(h - old.height) > 0.01 else { return }
        var new = old
        new.width = w
        new.height = h
        edit { perform(.setInlineImage(index, id: id, old: old, new: new)) }
    }

    /// Set the alternative text of the picture at `index` (a picture in its own paragraph), or of the inline picture
    /// `inline` of that paragraph, one undo step.
    /// `title` (the alt text's short title) is left as it was when nil.
    public func setImageAltText(at index: Int, inline id: String? = nil, _ text: String, title: String? = nil) {
        guard index < document.paragraphs.count else { return }
        if let id {
            guard var new = document.paragraphs[index].inlineImages[id],
                  new.altText != text || (title != nil && new.altTitle != title!) else { return }
            let old = new
            new.altText = text
            if let title { new.altTitle = title }
            edit { perform(.setInlineImage(index, id: id, old: old, new: new)) }
        } else {
            guard var new = document.paragraphs[index].image,
                  new.altText != text || (title != nil && new.altTitle != title!) else { return }
            let old = new
            new.altText = text
            if let title { new.altTitle = title }
            edit { perform(.setImage(index, old: old, new: new)) }
        }
    }

    /// Cut `crop` (shares of the picture's pixels, each side) off the picture at `index` or its inline picture `id`, one undo
    /// step. The picture keeps its scale: its frame shrinks or grows by the visible share, so nothing is stretched. nil
    /// shows the whole picture again. A crop that would leave under 5% in either direction is refused (returns false).
    @discardableResult
    public func setImageCrop(at index: Int, inline id: String? = nil, _ crop: PictureCrop?) -> Bool {
        guard index < document.paragraphs.count else { return false }
        guard let old = id.map({ document.paragraphs[index].inlineImages[$0] }) ?? document.paragraphs[index].image else { return false }
        let c = crop.flatMap { $0.left > 0 || $0.top > 0 || $0.right > 0 || $0.bottom > 0 ? $0 : nil }
        if let c {
            guard c.left >= 0, c.top >= 0, c.right >= 0, c.bottom >= 0, 1 - c.left - c.right >= 0.05, 1 - c.top - c.bottom >= 0.05 else { return false }
        }
        guard c != old.crop else { return true }
        let was = old.crop ?? PictureCrop(left: 0, top: 0, right: 0, bottom: 0)
        let now = c ?? PictureCrop(left: 0, top: 0, right: 0, bottom: 0)
        var new = old
        new.crop = c
        new.width = max(4, old.width * (1 - now.left - now.right) / max(0.01, 1 - was.left - was.right))
        new.height = max(4, old.height * (1 - now.top - now.bottom) / max(0.01, 1 - was.top - was.bottom))
        edit { perform(id.map { .setInlineImage(index, id: $0, old: old, new: new) } ?? .setImage(index, old: old, new: new)) }
        return true
    }

    /// Turn the picture at `index` (or its inline picture `id`) a quarter turn: `quarters` of 1 is clockwise, -1 anticlockwise. The
    /// picture's box swaps width and height (it stands in its turned box), one undo step. Returns false when `quarters` is a
    /// whole turn, there is no picture, or the picture floats (a floating picture keeps its unturned size: W-OB-3).
    @discardableResult
    public func rotatePicture(at index: Int, inline id: String? = nil, quarters: Int) -> Bool {
        guard index < document.paragraphs.count, quarters % 4 != 0 else { return false }
        guard let old = id.map({ document.paragraphs[index].inlineImages[$0] }) ?? document.paragraphs[index].image else { return false }
        guard old.float == nil else { return false }
        var new = old
        let degrees = (old.rotation + Double(quarters % 4) * 90).truncatingRemainder(dividingBy: 360)
        new.rotation = degrees < 0 ? degrees + 360 : degrees
        if quarters % 2 != 0 { swap(&new.width, &new.height) }
        edit { perform(id.map { .setInlineImage(index, id: $0, old: old, new: new) } ?? .setImage(index, old: old, new: new)) }
        return true
    }

    /// Swap the pixels of the picture at `index` (or its inline picture `id`) for `data`, one undo step. The picture keeps its
    /// width and its alternative text; its height follows the new picture's shape so nothing is stretched. The old
    /// picture's own markup (crop, effects) is dropped, as a replacement starts afresh. A floating picture is not replaced
    /// here (its anchor would be lost): returns false.
    @discardableResult
    public func replacePicture(at index: Int, inline id: String? = nil, with data: Data, name: String,
                               naturalWidth: Double, naturalHeight: Double) -> Bool {
        guard index < document.paragraphs.count, naturalWidth > 0, naturalHeight > 0 else { return false }
        guard let old = id.map({ document.paragraphs[index].inlineImages[$0] }) ?? document.paragraphs[index].image,
              old.float == nil, !old.data.isEmpty else { return false }
        var new = old
        new.data = data
        new.name = name
        new.naturalWidth = naturalWidth
        new.naturalHeight = naturalHeight
        new.height = max(4, old.width * naturalHeight / naturalWidth)
        new.crop = nil
        new.sourceXML = nil
        new.sourceRels = []
        new.sourceWidth = nil
        new.sourceHeight = nil
        new.sourceRunPropertiesXML = nil
        edit { perform(id.map { .setInlineImage(index, id: $0, old: old, new: new) } ?? .setImage(index, old: old, new: new)) }
        return true
    }

    /// Reset Picture: take the crop and the turn off the picture at `index` (or its inline picture `id`) and show it at its own size
    /// (the scale it had, when the file does not say what its own size is), one undo step. False when nothing changes.
    @discardableResult
    public func resetPicture(at index: Int, inline id: String? = nil) -> Bool {
        guard index < document.paragraphs.count else { return false }
        guard let old = id.map({ document.paragraphs[index].inlineImages[$0] }) ?? document.paragraphs[index].image else { return false }
        var new = old
        let was = old.crop ?? PictureCrop(left: 0, top: 0, right: 0, bottom: 0)
        new.crop = nil
        new.rotation = 0
        if let nw = old.naturalWidth, let nh = old.naturalHeight, nw > 0, nh > 0 {
            new.width = nw; new.height = nh
        } else {
            let turned = Int((old.rotation / 90).rounded()) % 2 != 0
            let (bw, bh) = turned ? (old.height, old.width) : (old.width, old.height)
            new.width = bw / max(0.01, 1 - was.left - was.right)
            new.height = bh / max(0.01, 1 - was.top - was.bottom)
        }
        guard new != old else { return false }
        edit { perform(id.map { .setInlineImage(index, id: $0, old: old, new: new) } ?? .setImage(index, old: old, new: new)) }
        return true
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
            _joinParagraphs(pos.paragraph - 1)
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
            // Tracked, the caret steps past the text it marked, as Word's does.
            let kept = _deleteRange(in: pos.paragraph, pos.offset ..< to)
            _setCaret(RichPosition(paragraph: pos.paragraph, offset: pos.offset + kept))
            return
        } else if pos.paragraph + 1 < document.paragraphs.count {
            if !_joinParagraphs(pos.paragraph) { _setCaret(RichPosition(paragraph: pos.paragraph + 1, offset: 0)); return }
        }
        _setCaret(pos)
    }

    public func deleteSelection() {
        guard !_selectionLocked() else { return }
        guard hasSelection else { return }
        edit { _deleteSelectionOps() }
    }

    /// Delete `range` of a paragraph. With track changes on, the text stays, marked deleted by the reviewer,
    /// as Word records a deletion (`w:del`); only the reviewer's own insertions really go, and text already
    /// deleted is left as it is. Returns how many units of the range are still there.
    @discardableResult
    private func _deleteRange(in paragraph: Int, _ range: Range<Int>) -> Int {
        guard range.upperBound > range.lowerBound else { return 0 }
        if let mark = _deletionMark() { return _trackDeletion(in: paragraph, range, mark) }
        _removeRange(in: paragraph, range)
        return 0
    }

    private func _removeRange(in paragraph: Int, _ range: Range<Int>) {
        let para = document.paragraphs[paragraph]
        let a = String.Index(utf16Offset: range.lowerBound, in: para.text)
        let b = String.Index(utf16Offset: range.upperBound, in: para.text)
        let text = String(para.text[a ..< b])
        perform(.deleteText(RichPosition(paragraph: paragraph, offset: range.lowerBound),
                            text, para.runs(in: range)))
    }

    /// The run properties the save writes for a style (inside `w:rPr`); the app sets it. With track changes
    /// on, a run whose properties change keeps the ones it had before (`w:rPrChange`).
    public nonisolated(unsafe) static var runPropertiesXML: ((CharStyle) -> String)? = nil

    /// With track changes on, formatting is recorded as Word records it: a run or paragraph whose properties
    /// change takes a format change by the reviewer holding the properties it had before. A second change
    /// keeps the first one's "before", as Word's does. The reviewer's own new text is just formatted.
    func _trackingFormat(_ op: EditOp) -> EditOp {
        switch op {
        case .setRuns(let i, let old, let new):
            guard let xml = Self.runPropertiesXML else { return op }
            return .setRuns(i, old: old, new: _trackedRuns(old, new, xml))
        case .setParagraphStyle(let i, let old, var new):
            guard new.propertyChange == old.propertyChange, Self._formatOnly(old) != Self._formatOnly(new) else { return op }
            let who = Self.reviewer()
            new.propertyChange = old.propertyChange ?? FormatChange(author: who.author, date: who.date, oldRPrXML: "",
                                                                    previous: .paragraph(Self._formatOnly(old)))
            return .setParagraphStyle(i, old: old, new: new)
        default: return op
        }
    }

    /// A paragraph style without its tracked changes and mark: what a paragraph format change compares.
    static func _formatOnly(_ s: RichParagraphStyle) -> RichParagraphStyle {
        var out = s; out.markRevision = nil; out.propertyChange = nil; out.mark = nil
        return out
    }

    private func _trackedRuns(_ old: [Run], _ new: [Run], _ xml: (CharStyle) -> String) -> [Run] {
        func plain(_ s: CharStyle) -> CharStyle { var p = s; p.revision = nil; p.formatChange = nil; return p }
        let who = Self.reviewer()
        var out: [Run] = []
        var oi = 0, ni = 0, oUsed = 0, nUsed = 0
        while oi < old.count, ni < new.count {
            let n = min(old[oi].length - oUsed, new[ni].length - nUsed)
            let o = old[oi].style
            var s = new[ni].style
            let own = o.revision?.kind == .inserted && !(o.revision?.moved ?? false) && o.revision?.author == who.author
            if n > 0, !own, s.formatChange == o.formatChange, xml(plain(o)) != xml(plain(s)) {
                s.formatChange = o.formatChange ?? FormatChange(author: who.author, date: who.date,
                                                                oldRPrXML: "<w:rPr>" + xml(plain(o)) + "</w:rPr>")
            }
            if n > 0 {
                if let last = out.last, last.style == s { out[out.count - 1].length += n } else { out.append(Run(length: n, style: s)) }
            }
            oUsed += n; nUsed += n
            if oUsed >= old[oi].length { oi += 1; oUsed = 0 }
            if nUsed >= new[ni].length { ni += 1; nUsed = 0 }
        }
        // (Lengths differ only if the op is not a restyle; keep whatever is left as given.)
        if ni < new.count { out.append(contentsOf: new[ni...].enumerated().map { k, r in k == 0 ? Run(length: r.length - nUsed, style: r.style) : r }) }
        return out
    }

    /// A deletion by the reviewer, now; nil with track changes off.
    func _deletionMark() -> RevisionMark? {
        guard document.trackRevisions else { return nil }
        let who = Self.reviewer()
        return RevisionMark(kind: .deleted, author: who.author, date: who.date)
    }

    /// Whether a tracked change is the reviewer's own insertion, which deleting takes away rather than
    /// marking (Word does the same: deleting what you typed leaves no trace).
    func _ownInsertion(_ mark: RevisionMark?, _ deletion: RevisionMark) -> Bool {
        guard let mark, mark.kind == .inserted, !mark.moved else { return false }
        return mark.author == deletion.author
    }

    private func _trackDeletion(in paragraph: Int, _ range: Range<Int>, _ mark: RevisionMark) -> Int {
        var own: [Range<Int>] = []
        var pos = 0
        for run in document.paragraphs[paragraph].runs {
            let lo = max(pos, range.lowerBound), hi = min(pos + run.length, range.upperBound)
            pos += run.length
            if hi > lo, _ownInsertion(run.style.revision, mark) {
                if let last = own.last, last.upperBound == lo { own[own.count - 1] = last.lowerBound ..< hi } else { own.append(lo ..< hi) }
            }
        }
        for r in own.reversed() { _removeRange(in: paragraph, r) }
        let kept = range.count - own.reduce(0) { $0 + $1.count }
        guard kept > 0 else { return 0 }
        var para = document.paragraphs[paragraph]
        let old = para.runs
        para.applyStyle(range.lowerBound ..< range.lowerBound + kept) { s in
            if s.revision?.kind != .deleted { s.revision = mark }
        }
        if para.runs != old { perform(.setRuns(paragraph, old: old, new: para.runs)) }
        return kept
    }

    /// Join paragraph `index + 1` onto `index`, or with track changes on mark `index`'s paragraph mark
    /// deleted (a mark the reviewer inserted goes, as their text does). Returns whether they joined.
    @discardableResult
    private func _joinParagraphs(_ index: Int) -> Bool {
        if let mark = _deletionMark(), !_ownInsertion(document.paragraphs[index].style.markRevision, mark) {
            let old = document.paragraphs[index].style
            if old.markRevision?.kind != .deleted {
                var marked = old; marked.markRevision = mark
                perform(.setParagraphStyle(index, old: old, new: marked))
            }
            return false
        }
        let tail = document.paragraphs[index + 1].style
        let ownMark = document.paragraphs[index].style.markRevision
        perform(.mergeParagraph(index, removedStyle: tail))
        // The mark that goes is the one ending `index`; what is left ends with the next paragraph's.
        if ownMark != nil, document.paragraphs[index].style.markRevision != tail.markRevision {
            let old = document.paragraphs[index].style
            var joined = old; joined.markRevision = tail.markRevision
            perform(.setParagraphStyle(index, old: old, new: joined))
        }
        return true
    }

    /// Remove the selection's contents; caret lands at its start.
    func _deleteSelectionOps() {
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
            let kept = _deleteRange(in: a.paragraph, a.offset ..< b.offset)
            _setCaret(RichPosition(paragraph: a.paragraph, offset: a.offset + kept))
            return
        } else if _crossesCellWall(a, b),
                  document.paragraphs[a.paragraph].cell != nil || document.paragraphs[b.paragraph].cell != nil {
            // A range that leaves a cell (or enters one) clears what it
            // covers and keeps every paragraph: cells never merge into
            // the text around them, and a cell never loses its last one.
            // (A range with both ends in body text holds any table between
            // them whole, and takes it away with the rest, below: Select
            // All and Delete leaves no empty table behind.)
            for i in a.paragraph ... b.paragraph {
                let len = document.paragraphs[i].length
                let lo = i == a.paragraph ? a.offset : 0
                let hi = i == b.paragraph ? b.offset : len
                _deleteRange(in: i, lo ..< hi)
            }
        } else {
            if _deletionMark() != nil {
                // Tracked: every paragraph keeps its place; the text and the marks between are marked
                // deleted, and the caret goes after them, where Word's goes (typing over a selection
                // writes the new text after the deleted).
                var i = a.paragraph, last = b.paragraph, lo = a.offset, endOffset = b.offset
                while true {
                    let hi = i == last ? endOffset : document.paragraphs[i].length
                    let end = lo + _deleteRange(in: i, lo ..< hi)
                    if i == last { _setCaret(RichPosition(paragraph: i, offset: end)); break }
                    if _joinParagraphs(i) {  // the next paragraph now goes on at `end`
                        if i + 1 == last { endOffset += end }
                        last -= 1; lo = end
                    } else { i += 1; lo = 0 }
                }
                return
            }
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

    func _setCaret(_ p: RichPosition) {
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

    /// Where formatting goes instead of this document (S-TX-1): set on a stand-in that shows shapes selected with no caret in them, so
    /// the ribbon's Font and Paragraph commands (and Clear Formatting) reach all of their text. Each command calls the relay once
    /// with what it would do to a controller.
    public var formatRelay: ((_ apply: (RichDocumentController) -> Void) -> Void)?

    /// Apply `transform` to the selection's runs, or to the typing style at
    /// a collapsed caret.
    public func applyCharStyle(_ transform: @escaping (inout CharStyle) -> Void) {
        if let relay = formatRelay { relay { $0.applyCharStyle(transform) }; return }
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
        guard !_selectionLocked() else { return }
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
            if let dash = before.findRange(of: "--", backwards: true),
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
            let style = _typed(typingStyle ?? document.paragraphs[pos.paragraph].style(at: pos.offset))
            // (Tracked, the replaced text stays, deleted, and the replacement follows it, as in Word.)
            let at = pos.offset - units + _deleteRange(in: pos.paragraph, (pos.offset - units) ..< pos.offset)
            perform(.insertText(RichPosition(paragraph: pos.paragraph, offset: at), replacement,
                                [Run(length: replacement.utf16.count, style: style)]))
            _setCaret(RichPosition(paragraph: pos.paragraph, offset: at + replacement.utf16.count))
        }
    }

    /// ⇧⏎: a line break inside the paragraph, not a new paragraph.
    public func insertLineBreak() {
        guard !_selectionLocked() else { return }
        edit(kind: .typing) {
            if hasSelection { _deleteSelectionOps() }
            let pos = selection.focus
            let para = document.paragraphs[pos.paragraph]
            guard !para.isImage else { return }
            let style = _typed(typingStyle ?? para.style(at: pos.offset))
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
            // Replacing text takes the style of what it replaces — an IME's
            // commit keeps the style its marked text was typed in — and an
            // insertion the style before it, as typing does.
            let style = _typed(typingStyle ?? para.style(at: hi > lo ? lo + 1 : lo))
            let at = hi > lo ? lo + _deleteRange(in: index, lo ..< hi) : lo
            if !text.isEmpty {
                perform(.insertText(RichPosition(paragraph: index, offset: at), text,
                                    [Run(length: text.utf16.count, style: style)]))
            }
            _setCaret(RichPosition(paragraph: index, offset: at + text.utf16.count))
        }
    }

    /// Flip content-control check box `id` of paragraph `index` (one undo step). Returns whether it changed.
    @discardableResult
    public func toggleCheckBox(in index: Int, control id: Int) -> Bool {
        guard index >= 0, index < document.paragraphs.count,
              let box = document.paragraphs[index].checkBoxes.first(where: { $0.id == id }),
              let after = document.paragraphs[index].settingCheckBox(id, to: !box.checked) else { return false }
        edit { perform(.restoreParagraphs(index, count: 1, [after])) }
        return true
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
                let at = lo + _deleteRange(in: i, lo ..< hi)
                perform(.insertText(RichPosition(paragraph: i, offset: at), newText,
                                    newRuns.map { r in var r = r; r.style = _typed(r.style); return r }))
                if block == nil, i == end.paragraph {
                    selection = RichSelection(anchor: start, focus: RichPosition(paragraph: i, offset: at + newText.utf16.count))
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
        edit(kind: coalescing ? .styleEdit : .other) {
            perform(.setStyleEntry(old: old, new: entry))
            // Paragraph props are stored on each paragraph: those that still
            // hold the old entry's value follow the new one, as in Word.
            for i in document.paragraphs.indices where document.styles.id(of: document.paragraphs[i].style) == entry.id {
                let before = document.paragraphs[i].style
                var after = before
                func follow<T: Equatable>(_ k: WritableKeyPath<RichParagraphStyle, T>) {
                    if before[keyPath: k] == old.paragraph[keyPath: k] { after[keyPath: k] = entry.paragraph[keyPath: k] }
                }
                follow(\.alignment); follow(\.indentLeft); follow(\.indentRight); follow(\.firstLineIndent)
                follow(\.spaceBefore); follow(\.spaceAfter); follow(\.lineSpacing)
                if after != before { perform(.setParagraphStyle(i, old: before, new: after)) }
            }
        }
    }

    /// Word's "Update <style> to Match Selection": the caret's character
    /// formatting and paragraph props become the sheet's entry, so every
    /// paragraph in that style changes. One undo step.
    public func updateStyleToMatchSelection(_ id: String) {
        guard var entry = document.styles[id] else { return }
        let old = entry
        var char = currentCharStyle
        char.link = nil; char.linkTip = nil
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

    /// Create a style named `name` from the caret's formatting and apply it
    /// to the selected paragraphs. Returns the new id, or nil for an empty
    /// or already-used name.
    @discardableResult
    public func createStyleFromSelection(name: String) -> String? {
        var name = name
        while name.first == " " { name.removeFirst() }
        while name.last == " " { name.removeLast() }
        guard !name.isEmpty,
              !document.styles.styles.contains(where: { $0.name.lowercased() == name.lowercased() }) else { return nil }
        var id = String(name.filter { $0.isLetter || $0.isNumber })
        if id.isEmpty { id = "Style" }
        var unique = id, n = 2
        while document.styles[unique] != nil { unique = "\(id)\(n)"; n += 1 }
        var char = currentCharStyle
        char.link = nil; char.linkTip = nil; char.highlight = nil
        var ps = currentParagraphStyle
        ps.list = nil; ps.listLevel = 0; ps.listId = nil; ps.pageBreakBefore = false
        ps.named = unique; ps.heading = nil
        let entry = RichNamedStyle(id: unique, name: name, paragraph: ps, char: char, next: unique)
        edit {
            perform(.addStyle(entry))
            let sheet = document.styles
            applyParagraphStyle { sheet.apply(unique, to: &$0) }
            // The style now holds them: no direct copy stays on the source.
            for i in document.paragraphIndices(in: selection) {
                var para = document.paragraphs[i]
                let old = para.runs
                para.applyStyle(0 ..< para.length) { Self._clearHeld(by: char, &$0) }
                if para.runs != old { perform(.setRuns(i, old: old, new: para.runs)) }
            }
        }
        return unique
    }

    /// Reset the character properties `style` equals the style's to
    /// their defaults, so the style, not a direct copy, supplies them.
    static func _clearHeld(by held: CharStyle, _ style: inout CharStyle) {
        let none = CharStyle()
        if style.bold == held.bold { style.bold = none.bold }
        if style.italic == held.italic { style.italic = none.italic }
        if style.underline == held.underline { style.underline = none.underline; style.underlineKind = none.underlineKind }
        if style.strikethrough == held.strikethrough { style.strikethrough = none.strikethrough }
        if style.fontFamily == held.fontFamily { style.fontFamily = none.fontFamily }
        if style.fontSize == held.fontSize { style.fontSize = none.fontSize }
        if style.color == held.color { style.color = none.color }
    }

    /// Delete the style `id`; paragraphs in it go back to Normal. Normal
    /// and the headings stay. One undo step.
    public func deleteStyle(_ id: String) {
        guard id != RichNamedStyle.normalId, !id.hasPrefix("Heading"), let entry = document.styles[id] else { return }
        edit {
            let sheet = document.styles
            for i in document.paragraphs.indices where document.paragraphs[i].style.named == id {
                let old = document.paragraphs[i].style
                var new = old
                sheet.apply(RichNamedStyle.normalId, to: &new)
                new.named = nil
                if new != old { perform(.setParagraphStyle(i, old: old, new: new)) }
            }
            // Another style whose "next" was this one points at Normal, as Word does.
            for other in document.styles.styles where other.id != id && other.next == id {
                var moved = other
                moved.next = RichNamedStyle.normalId
                perform(.setStyleEntry(old: other, new: moved))
            }
            perform(.removeStyle(entry))
        }
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

    /// Returns the state it set, for the keyboard's announcement.
    @discardableResult public func toggleBold() -> Bool {
        let on = !selectionAll { $0.bold }
        applyCharStyle { $0.bold = on }
        return on
    }

    /// Returns the state it set, for the keyboard's announcement.
    @discardableResult public func toggleItalic() -> Bool {
        let on = !selectionAll { $0.italic }
        applyCharStyle { $0.italic = on }
        return on
    }

    /// Returns the state it set, for the keyboard's announcement.
    @discardableResult public func toggleUnderline() -> Bool {
        let on = !selectionAll { $0.underline }
        applyCharStyle { $0.underline = on }
        return on
    }

    public func toggleStrikethrough() {
        let on = !selectionAll { $0.strikethrough }
        applyCharStyle { $0.strikethrough = on }
    }

    /// Everything the Font dialog sets, applied as one undo step. Each field
    /// replaces the run's value; nil means "none" (the style's own).
    public struct CharFormat: Equatable {
        public var family: String?
        public var size: Double?
        public var bold = false, italic = false, underline = false
        public var strikethrough = false, doubleStrike = false
        public var script: ScriptPosition = .normal
        public var smallCaps = false, caps = false, hidden = false
        public var spacing: Double?       // points between letters
        public var scale: Double?         // horizontal scale, 1 = 100%
        public var raised: Double?        // points up (negative: down)
        public var kerningFrom: Double?   // kern from this size, points
        /// The underline's kind as Word names it (`w:u w:val`: "words", "double", "thick", "dotted", "dash", "wave"...); nil is single.
        public var underlineKind: String?
        /// The underline's own colour, "RRGGBB"; nil follows the text.
        public var underlineColor: String?
        /// The face for Asian text (`w:rFonts w:eastAsia`); nil leaves it to the style.
        public var eastAsiaFamily: String?
        public init() {}
        public init(_ s: CharStyle) {
            family = s.fontFamily; size = s.fontSize
            bold = s.bold; italic = s.italic; underline = s.underline
            strikethrough = s.strikethrough && !s.doubleStrike; doubleStrike = s.doubleStrike
            script = s.script; smallCaps = s.smallCaps; caps = s.caps; hidden = s.hidden
            spacing = s.letterSpacing; scale = s.horizontalScale
            raised = s.raised; kerningFrom = s.kerningFrom
            underlineKind = s.underline ? s.underlineKind : nil
            underlineColor = s.underline ? s.underlineColor : nil
            eastAsiaFamily = s.eastAsiaFontFamily
        }
    }

    public func setCharFormat(_ f: CharFormat) {
        applyCharStyle { s in
            s.fontFamily = f.family; s.fontSize = f.size
            s.bold = f.bold; s.italic = f.italic; s.underline = f.underline
            s.strikethrough = f.strikethrough || f.doubleStrike; s.doubleStrike = f.doubleStrike
            s.script = f.script; s.smallCaps = f.smallCaps; s.caps = f.caps; s.hidden = f.hidden
            s.letterSpacing = f.spacing
            s.horizontalScale = (f.scale ?? 1) == 1 ? nil : f.scale
            s.raised = (f.raised ?? 0) == 0 ? nil : f.raised
            s.kerningFrom = f.kerningFrom
            // A kind or colour the dialog left as it found them keeps the run's theme colour attributes.
            if s.underlineKind != f.underlineKind || s.underlineColor != f.underlineColor || !f.underline {
                s.underlineKind = f.underline ? f.underlineKind : nil
                s.underlineColor = f.underline ? f.underlineColor : nil
                s.underlineThemeAttrs = nil
            }
            s.eastAsiaFontFamily = f.eastAsiaFamily
        }
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
        if let relay = formatRelay { relay { $0.clearFormatting() }; return }
        // Plain, but the hyperlink, a footnote mark, an inline picture and
        // tracked-change marks are content, not formatting: they stay.
        let keep: (inout CharStyle) -> Void = { s in
            var p = CharStyle.plain
            p.link = s.link; p.linkTip = s.linkTip; p.note = s.note; p.inlineImage = s.inlineImage
            p.revision = s.revision; p.formatChange = s.formatChange
            s = p
        }
        edit {
            let a = document.clamped(selection.start)
            let b = document.clamped(selection.end)
            for i in document.paragraphIndices(in: selection) {
                let old = document.paragraphs[i]
                var para = old
                if selection.block == nil, selection.isCollapsed || (a.paragraph == b.paragraph) {
                    let lo = a.paragraph == b.paragraph ? a.offset : 0
                    let hi = a.paragraph == b.paragraph ? b.offset : para.length
                    para.applyStyle(lo ..< hi, keep)
                } else {
                    para.applyStyle(0 ..< para.length, keep)
                }
                if para.runs != old.runs { perform(.setRuns(i, old: old.runs, new: para.runs)) }
                if old.style != .body { perform(.setParagraphStyle(i, old: old.style, new: .body)) }
            }
            typingStyle = selection.isCollapsed ? .plain : nil
        }
    }

    // MARK: Paragraph formatting

    public func setLineSpacing(_ multiple: Double) {
        setParagraphFormat(ParagraphFormat(lineRule: .multiple(multiple)))
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

    /// How a paragraph's line height is set: a multiple of the font's natural
    /// height, or a fixed number of points (at least / exactly).
    public enum LineRule: Equatable {
        case multiple(Double)
        case atLeast(Double)
        case exactly(Double)
    }

    /// Every setting of a Paragraph dialog. A nil field is left as it is.
    /// One call is one undo step.
    public struct ParagraphFormat: Equatable {
        public var alignment: ParagraphAlignment?
        public var indentLeft: Double?
        public var indentRight: Double?
        /// Positive = first line indented, negative = hanging, 0 = none.
        public var firstLineIndent: Double?
        public var spaceBefore: Double?
        public var spaceAfter: Double?
        public var lineRule: LineRule?
        /// The paragraph's whole list of tab stops (nil leaves them as they are).
        public var tabStops: [TabStop]?
        /// Word's "Don't add space between paragraphs of the same style" (w:contextualSpacing); nil leaves it.
        public var contextualSpacing: Bool?
        public init(alignment: ParagraphAlignment? = nil, indentLeft: Double? = nil,
                    indentRight: Double? = nil, firstLineIndent: Double? = nil,
                    spaceBefore: Double? = nil, spaceAfter: Double? = nil,
                    lineRule: LineRule? = nil, tabStops: [TabStop]? = nil, contextualSpacing: Bool? = nil) {
            self.tabStops = tabStops; self.contextualSpacing = contextualSpacing
            self.alignment = alignment; self.indentLeft = indentLeft
            self.indentRight = indentRight; self.firstLineIndent = firstLineIndent
            self.spaceBefore = spaceBefore; self.spaceAfter = spaceAfter
            self.lineRule = lineRule
        }
    }

    public func setParagraphFormat(_ f: ParagraphFormat) {
        applyParagraphStyle { s in
            if let a = f.alignment { s.alignment = a }
            if let v = f.indentLeft { s.indentLeft = max(0, v) }
            if let v = f.indentRight { s.indentRight = max(0, v) }
            if let v = f.firstLineIndent { s.firstLineIndent = v }
            if let v = f.spaceBefore { s.spaceBefore = max(0, v); s.spaceBeforeAuto = false }
            if let v = f.spaceAfter { s.spaceAfter = max(0, v); s.spaceAfterAuto = false }
            if let c = f.contextualSpacing { s.contextualSpacing = c }
            if let t = f.tabStops { s.tabStops = t.filter { $0.position >= 0 }.sorted { $0.position < $1.position } }
            switch f.lineRule {
            case .multiple(let m)?:
                s.lineSpacing = max(0.1, m); s.lineHeightPoints = nil; s.lineHeightIsMinimum = false
            case .atLeast(let p)?:
                s.lineHeightPoints = max(1, p); s.lineHeightIsMinimum = true
            case .exactly(let p)?:
                s.lineHeightPoints = max(1, p); s.lineHeightIsMinimum = false
            case nil: break
            }
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

    /// W-PA-6: start the next column at the caret (Word's Ctrl+Shift+Enter): the text after it becomes a paragraph
    /// whose column break ends the one before, as a `w:br w:type="column"` read from a file is held. One undo step.
    public func insertColumnBreak() {
        edit {
            if hasSelection { _deleteSelectionOps() }
            let pos = selection.focus
            var tailStyle = document.paragraphs[pos.paragraph].style
            tailStyle.pageBreakBefore = true; tailStyle.breakEndsPrevious = true; tailStyle.columnBreak = true
            tailStyle.pageBreakInline = false
            perform(.splitParagraph(pos, tailStyle: tailStyle))
            _setCaret(RichPosition(paragraph: pos.paragraph + 1, offset: 0))
        }
    }

    /// How the section a section break opens starts (Word's Layout > Breaks): its `w:type`.
    public enum SectionBreakKind: String, CaseIterable, Sendable { case nextPage, continuous, evenPage, oddPage }

    /// A section mark's `sectionXML` that stands for a copy of the last section as the file writes it (its header and footer
    /// parts, page, columns and grid), with its own `w:type`: what a section break made in the last section holds.
    public static let sectionAsLast = "x-asLast"

    /// W-PA-6: end a section at the caret (Layout > Breaks > Next Page, Continuous, Even Page, Odd Page). The text before the
    /// caret becomes a section with the caret's section's page, headers and start; the text after it starts as `kind` says.
    /// One undo step.
    public func insertSectionBreak(_ kind: SectionBreakKind, lastSetup: PageSetup) {
        guard document.paragraphs[selection.focus.paragraph].cell == nil else { return }
        edit {
            if hasSelection { _deleteSelectionOps() }
            let pos = selection.focus
            let mark = sectionMark(containing: pos.paragraph)
            let own = document.paragraphs[pos.paragraph].style
            let markStyle = mark >= 0 ? document.paragraphs[mark].style : nil
            let page = markStyle?.sectionPage ?? document.lastSectionPage ?? lastSetup
            var head = own
            head.sectionPage = page
            head.sectionXML = markStyle?.sectionXML
                ?? "<w:sectPr \(Self.sectionAsLast)=\"1\">\(document.sectionTypeXML ?? "")</w:sectPr>"
            head.sectionRels = markStyle?.sectionRels ?? []
            head.sectionBreaksPage = kind != .continuous
            var tail = own
            // (As the reader holds a section that starts a page: its first paragraph breaks before, unwritten.)
            tail.pageBreakBefore = kind != .continuous
            tail.breakEndsPrevious = false; tail.columnBreak = false; tail.pageBreakInline = false
            if mark != pos.paragraph { tail.sectionXML = nil; tail.sectionPage = nil; tail.sectionRels = []; tail.sectionBreaksPage = nil }
            perform(.splitParagraph(pos, tailStyle: tail))
            perform(.setParagraphStyle(pos.paragraph, old: document.paragraphs[pos.paragraph].style, new: head))
            // The section after the break starts as `kind` says (a section's w:type is how IT starts).
            let type = "<w:type w:val=\"\(kind.rawValue)\"/>"
            var next = page
            next.sectionStartParity = kind == .evenPage ? .even : kind == .oddPage ? .odd : nil
            if mark < 0 {
                perform(.setLastSectionType(old: document.sectionTypeXML, new: type))
                if next != page || document.lastSectionPage != nil {
                    perform(.setSectionPage(-1, old: document.lastSectionPage, new: next))
                }
            } else {
                let at = mark + 1
                var style = document.paragraphs[at].style
                style.sectionPage = next
                style.sectionXML = style.sectionXML.map { Self._sectionXML($0, type: type) }
                perform(.setParagraphStyle(at, old: document.paragraphs[at].style, new: style))
            }
            _setCaret(RichPosition(paragraph: pos.paragraph + 1, offset: 0))
        }
    }

    /// `xml` (a `w:sectPr`) with its `w:type` replaced by `type`, in schema order (after the header, footer and note
    /// properties, before the page size).
    static func _sectionXML(_ xml: String, type: String) -> String {
        var out = xml
        if let open = out.rangeOfSubstring("<w:type "), let close = out[open.upperBound...].rangeOfSubstring("/>") {
            out.replaceSubrange(open.lowerBound ..< close.upperBound, with: type)
            return out
        }
        for tag in ["<w:pgSz", "<w:pgMar", "<w:paperSrc", "<w:pgBorders", "<w:lnNumType", "<w:pgNumType", "<w:cols", "<w:formProt",
                    "<w:vAlign", "<w:noEndnote", "<w:titlePg", "<w:textDirection", "<w:bidi", "<w:rtlGutter", "<w:docGrid",
                    "<w:printerSettings", "<w:sectPrChange", "</w:sectPr>"] {
            if let at = out.rangeOfSubstring(tag) { out.insert(contentsOf: type, at: at.lowerBound); return out }
        }
        return out
    }

    // MARK: Tables

    public var isInCell: Bool { document.paragraphs[selection.focus.paragraph].cell != nil }

    /// Insert an empty rows×columns table at the caret, with a plain
    /// paragraph after it so the caret can leave it.
    /// How a new table sizes its columns: `fixed` keeps the widths it is given,
    /// `contents` lets Word-style autofit follow the text, `window` also spans the text width.
    public enum TableFit: Sendable { case fixed, contents, window }

    public func insertTable(rows: Int, columns: Int, fit: TableFit = .contents) {
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
            // (At the start of a paragraph with text the table goes before it: no empty paragraph is left behind, as in Word.)
            if (para.text.isEmpty || pos.offset == 0) && !para.isImage && para.cell == nil {
                at = pos.paragraph
                // Word reads two tables with nothing between them as one: keep a paragraph.
                if at > 0, document.paragraphs[at - 1].cell != nil {
                    perform(.insertParagraphs(at: at, [RichParagraph()]))
                    at += 1
                }
                perform(.insertParagraphs(at: at, cells))
            } else if para.cell != nil {
                // A table inside a table is a step too far: put it after.
                let after = _tableEnd(from: pos.paragraph) + 1
                perform(.insertParagraphs(at: after, [RichParagraph()] + cells + [RichParagraph()]))
                at = after + 1
            } else {
                if pos.offset < para.length {
                    perform(.splitParagraph(pos, tailStyle: .body))
                } else {
                    perform(.insertParagraphs(at: at, [RichParagraph()]))
                }
                perform(.insertParagraphs(at: at, cells))
            }
            _setCaret(RichPosition(paragraph: at, offset: 0))
            var style = TableStyle()
            switch fit {
            case .contents: break
            case .fixed: style.fixedLayout = true
            case .window: style.widthPercent = 100
            }
            if style != TableStyle() { perform(.setTableStyle(id, old: nil, new: style)) }
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

    /// Convert Text to Table / Table to Text: what separates the pieces.
    public enum TextTableSeparator: Equatable, Sendable {
        case paragraph, tab, comma, other(Character)
        var character: Character? {
            switch self {
            case .paragraph: return nil
            case .tab: return "\t"
            case .comma: return ","
            case .other(let c): return c
            }
        }
    }

    /// Whether the selection holds plain paragraphs a table can be made of.
    public var canConvertTextToTable: Bool {
        let lo = min(selection.anchor.paragraph, selection.focus.paragraph)
        let hi = max(selection.anchor.paragraph, selection.focus.paragraph)
        return (lo ... hi).contains { document.paragraphs[$0].cell == nil } && hasSelection
    }

    /// Make the selected paragraphs a table, one undo step. With a character separator each paragraph is a row and the
    /// character cuts it into cells; with `.paragraph` each paragraph is a cell, filled `columns` to a row.
    @discardableResult
    public func convertTextToTable(separator: TextTableSeparator, columns: Int = 1) -> Bool {
        guard hasSelection else { return false }
        let lo = min(selection.anchor.paragraph, selection.focus.paragraph)
        var hi = max(selection.anchor.paragraph, selection.focus.paragraph)
        let sel = selection
        // A selection ending at the very start of a paragraph leaves that paragraph out.
        let endP = sel.anchor.paragraph > sel.focus.paragraph || (sel.anchor.paragraph == sel.focus.paragraph && sel.anchor.offset > sel.focus.offset) ? sel.anchor : sel.focus
        if hi > lo, endP.offset == 0 { hi -= 1 }
        let source = Array(document.paragraphs[lo ... hi])
        guard !source.contains(where: { $0.cell != nil }) else { return false }
        var rowsOfCells: [[RichParagraph]] = []
        if let ch = separator.character {
            for var para in source {
                var cells: [RichParagraph] = []
                while let r = para.text.firstIndex(of: ch) {
                    let at = para.text.utf16.distance(from: para.text.startIndex, to: r)
                    var tail = para.split(at: at)
                    _ = tail.delete(0 ..< ch.utf16.count)
                    cells.append(para)
                    para = tail
                }
                cells.append(para)
                rowsOfCells.append(cells)
            }
        } else {
            let n = max(1, columns)
            var i = 0
            while i < source.count {
                rowsOfCells.append(Array(source[i ..< min(source.count, i + n)]))
                i += n
            }
        }
        let width = max(1, rowsOfCells.map(\.count).max() ?? 1)
        let id = UUID().uuidString
        var out: [RichParagraph] = []
        for (r, row) in rowsOfCells.enumerated() {
            for c in 0 ..< width {
                var p = c < row.count ? row[c] : RichParagraph()
                p.style = .cell
                p.cell = CellRef(table: id, row: r, column: c)
                out.append(p)
            }
        }
        edit {
            // (The table goes in before the source goes out, so the document is never left empty mid-edit.)
            var at = lo
            if at > 0, document.paragraphs[at - 1].cell != nil {
                perform(.insertParagraphs(at: at, [RichParagraph()]))
                at += 1
            }
            perform(.insertParagraphs(at: at, out))
            let sourceAt = at + out.count
            perform(.removeParagraphs(at: sourceAt, source))
            if sourceAt >= document.paragraphs.count || document.paragraphs[sourceAt].cell != nil {
                perform(.insertParagraphs(at: sourceAt, [RichParagraph()]))
            }
            _setCaret(RichPosition(paragraph: at, offset: 0))
        }
        return true
    }

    /// Turn the caret's table into text, one undo step. A character separator joins a row's cells into one paragraph;
    /// `.paragraph` makes every cell a paragraph of its own.
    @discardableResult
    public func convertTableToText(separator: TextTableSeparator) -> Bool {
        guard let range = currentTableRange, let id = document.paragraphs[range.lowerBound].cell?.table else { return false }
        let old = Array(document.paragraphs[range])
        var out: [RichParagraph] = []
        for (i, var p) in old.enumerated() {
            guard let cell = p.cell else { continue }
            let next = i + 1 < old.count ? old[i + 1].cell : nil
            // The last paragraph of a cell that has a neighbour in its row takes the separator after it.
            let endsCell = next == nil || next!.row != cell.row || next!.column != cell.column
            let rowContinues = next != nil && next!.row == cell.row
            p.cell = nil
            if p.style == .cell { p.style = .body }
            if let ch = separator.character, endsCell, rowContinues {
                p.append(RichParagraph(text: String(ch), charStyle: p.style(at: max(0, p.length - 1))))
                out.append(p)
            } else if separator.character != nil, endsCell == false {
                out.append(p)
            } else {
                out.append(p)
            }
        }
        // With a character separator the pieces of one row must share a paragraph.
        if separator.character != nil {
            var merged: [RichParagraph] = []
            var joinNext = false
            for (i, p) in out.enumerated() {
                let src = old[i].cell!
                let nextSame = i + 1 < old.count && old[i + 1].cell!.row == src.row
                let endsCell = i + 1 >= old.count || old[i + 1].cell!.column != src.column || old[i + 1].cell!.row != src.row
                if joinNext, !merged.isEmpty { merged[merged.count - 1].append(p) } else { merged.append(p) }
                joinNext = nextSame && endsCell
            }
            out = merged
        }
        edit {
            perform(.insertParagraphs(at: range.lowerBound, out))
            perform(.removeParagraphs(at: range.lowerBound + out.count, old))
            if document.tableStyles[id] != nil { perform(.setTableStyle(id, old: document.tableStyles[id], new: nil)) }
            _setCaret(RichPosition(paragraph: range.lowerBound, offset: 0))
        }
        return true
    }

    /// Table Layout > Sort: how a key's cells are compared.
    public enum TableSortKind: Equatable, Sendable { case text, number, date }
    public struct TableSortKey: Equatable, Sendable {
        public var column: Int
        public var kind: TableSortKind
        public var ascending: Bool
        public init(column: Int, kind: TableSortKind = .text, ascending: Bool = true) {
            self.column = column; self.kind = kind; self.ascending = ascending
        }
    }

    /// A table with no merged cells that the caret is in can be sorted.
    public var canSortTable: Bool {
        guard let r = currentTableRange else { return false }
        return !document.paragraphs[r].contains { ($0.cell?.span ?? 1) > 1 || ($0.cell?.rowSpan ?? 1) > 1 }
    }

    /// The number a cell's text starts with (currency signs, spaces and thousands commas skipped), nil for none.
    static func sortNumber(_ text: String) -> Double? {
        var digits = ""
        var seen = false
        for ch in text {
            if ch.isNumber || (ch == "." && !digits.contains("." as Character)) || (ch == "-" && digits.isEmpty) { digits.append(ch); seen = seen || ch.isNumber }
            else if ch == "," && seen { continue }
            else if seen { break }
            else if ch == " " || ch == "$" || ch == "€" || ch == "£" || ch == "¥" || ch == "(" { continue }
            else { return nil }
        }
        return seen ? Double(digits) : nil
    }

    /// A date as a day count (year, month, day order), nil when the text is not one: 2024-03-05, 3/5/2024, Mar 5, 2024, 5 March 2024.
    static func sortDate(_ text: String) -> Double? {
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        var nums: [Int] = [], month: Int? = nil, word = "", num = ""
        func flushWord() { if word.count >= 3, month == nil, let m = months.firstIndex(of: String(word.lowercased().prefix(3))) { month = m + 1 }; word = "" }
        func flushNum() { if let n = Int(num) { nums.append(n) }; num = "" }
        let isoFirst = text.prefix(5).allSatisfy { $0.isNumber || $0 == "-" } && text.dropFirst(4).first == "-"
        for ch in text {
            if ch.isNumber { flushWord(); num.append(ch) }
            else if ch.isLetter { flushNum(); word.append(ch) }
            else { flushWord(); flushNum() }
        }
        flushWord(); flushNum()
        var y = 0, m = 0, d = 0
        if let mo = month, nums.count == 2 {
            m = mo
            if nums[0] > 31 { y = nums[0]; d = nums[1] } else { d = nums[0]; y = nums[1] }
        } else if month == nil, nums.count == 3 {
            if isoFirst || nums[0] > 31 { (y, m, d) = (nums[0], nums[1], nums[2]) } else { (m, d, y) = (nums[0], nums[1], nums[2]) }
        } else { return nil }
        if y < 100 { y += y < 50 ? 2000 : 1900 }
        guard (1 ... 12).contains(m), (1 ... 31).contains(d) else { return nil }
        return Double(y * 372 + m * 31 + d)
    }

    /// Sort the rows of the caret's table by up to three keys, one undo step. With `headerRow` the first row stays put.
    /// Rows with empty or unreadable cells come first when ascending. Stable: equal rows keep their order.
    @discardableResult
    public func sortTable(keys: [TableSortKey], headerRow: Bool) -> Bool {
        guard canSortTable, !keys.isEmpty, let range = currentTableRange else { return false }
        var rows: [[RichParagraph]] = []
        var last = -1
        for p in document.paragraphs[range] {
            guard let c = p.cell else { continue }
            if c.row != last { rows.append([]); last = c.row }
            rows[rows.count - 1].append(p)
        }
        let start = headerRow ? 1 : 0
        guard rows.count - start > 1 else { return false }
        func text(_ row: [RichParagraph], _ col: Int) -> String {
            row.filter { $0.cell?.column == col }.map(\.text).joined(separator: "\n")
                .drop(while: { $0 == " " }).reversed().drop(while: { $0 == " " }).reversed().map(String.init).joined()
        }
        func key(_ row: [RichParagraph], _ k: TableSortKey) -> (Double?, String) {
            let t = text(row, k.column)
            switch k.kind {
            case .text: return (nil, t.lowercased())
            case .number: return (RichDocumentController.sortNumber(t), t.lowercased())
            case .date: return (RichDocumentController.sortDate(t), t.lowercased())
            }
        }
        let body = Array(rows[start...]).enumerated().sorted { a, b in
            for k in keys.prefix(3) {
                let x = key(a.element, k), y = key(b.element, k)
                var order = 0
                if k.kind == .text { order = x.1 < y.1 ? -1 : (x.1 > y.1 ? 1 : 0) }
                else if x.0 == nil || y.0 == nil { order = (x.0 == nil && y.0 == nil) ? 0 : (x.0 == nil ? -1 : 1) }
                else { order = x.0! < y.0! ? -1 : (x.0! > y.0! ? 1 : 0) }
                if order != 0 { return k.ascending ? order < 0 : order > 0 }
            }
            return a.offset < b.offset
        }.map(\.element)
        let ordered = Array(rows[..<start]) + body
        if ordered.enumerated().allSatisfy({ i, r in r.first?.cell?.row == rows[i].first?.cell?.row && r.first?.text == rows[i].first?.text && r.map(\.text) == rows[i].map(\.text) }) { return true }
        _rewriteTable(caret: { _ in nil }, rewrite: { paras in
            var out: [RichParagraph] = []
            for (n, row) in ordered.enumerated() {
                for var p in row { p.cell?.row = rows[n].first?.cell?.row ?? n; out.append(p) }
            }
            paras = out
        })
        return true
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
        setTableStyle(of: t, transform)
    }

    /// The table's `w:tblLook` bits as they stand: the user's, else the file's, else Word's default (04A0).
    public func tableLook(of t: String) -> Int {
        if let l = document.tableStyles[t]?.look { return l }
        if let xml = document.tableLooks[t], let r = xml.rangeOfSubstring("w:val=\""),
           let e = xml.rangeOfSubstring("\"", in: r.upperBound ..< xml.endIndex),
           let v = Int(String(xml[r.upperBound ..< e.lowerBound]), radix: 16) { return v }
        return 0x04A0
    }

    /// Turn one Table Style Option on or off for the caret's table (`TableLook` bits), one undo step. Header Row is a look
    /// switch only; repeating the row on each page is the separate Repeat Header Rows setting.
    public func setTableLook(_ bit: Int, on: Bool) {
        guard let t = currentCell?.table else { return }
        let was = tableLook(of: t)
        let now = on ? was | bit : was & ~bit
        guard now != was else { return }
        // The style's header and band fills follow the switches: redrawn in the same undo step as the look.
        var new = document.tableStyles[t] ?? TableStyle()
        let oldStyle = document.tableStyles[t]
        new.look = now
        let fills = document.tableCondFills[t]
        let range = currentTableRange
        let oldParas = range.map { Array(document.paragraphs[$0]) }
        var paras = oldParas
        if let fills, paras != nil {
            let rows = (paras!.compactMap { $0.cell?.row }.max() ?? 0) + 1
            let cols = paras!.compactMap { $0.cell.map { $0.column + $0.span } }.max() ?? 1
            for i in paras!.indices {
                guard var c = paras![i].cell, c.table == t, c.fill == nil || c.styleFilled == true else { continue }
                c.fill = fills.fill(look: now, row: c.row, column: c.column, lastRow: c.row + c.rowSpan >= rows, lastColumn: c.column + c.span >= cols)
                c.styleFilled = c.fill == nil ? nil : true
                paras![i].cell = c
            }
        }
        let sel = selection
        edit {
            perform(.setTableStyle(t, old: oldStyle, new: new == TableStyle() ? nil : new))
            if let range, let oldParas, let paras, paras != oldParas {
                perform(.removeParagraphs(at: range.lowerBound, oldParas))
                perform(.insertParagraphs(at: range.lowerBound, paras))
                selection = sel
            }
        }
    }

    /// The same for a named table (a drag on a border of a table the caret is not in).
    public func setTableStyle(of t: String, _ transform: (inout TableStyle) -> Void) {
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

    /// Set by the editor: the laid-out height of the row a cell paragraph is in.
    public var rowHeightProbe: ((Int) -> Double?)?
    /// Where the floating picture at paragraph `index` (or its inline picture `id`) is drawn: its top and its paragraph's
    /// top, in points from the top of its page. Set by the editor that lays it out.
    public var pictureSpotProbe: ((Int, String?) -> (Double, Double)?)?

    /// Equal heights: every target row (the whole table when one row is chosen) gets the tallest of them.
    public func distributeRows() {
        guard let here = currentCell else { return }
        var rows = targetRows ?? (here.row ... here.row)
        if rows.count < 2 { rows = 0 ... Int.max / 2 }
        var heights: [Int: Double] = [:]
        for (i, p) in document.paragraphs.enumerated() {
            guard let c = p.cell, c.table == here.table, rows.contains(c.row), c.rowSpan == 1, heights[c.row] == nil,
                  let h = rowHeightProbe?(i) else { continue }
            heights[c.row] = h
        }
        guard let tallest = heights.values.max() else { return }
        setTableStyle { t in
            for r in heights.keys { t.rowHeights[r] = tallest; t.rowsExactHeight.remove(r) }
        }
    }

    /// AutoFit: to contents (grid follows the text), to window (full text width), or fixed column widths.
    public func autoFitTable(_ fit: TableFit) {
        switch fit {
        case .contents: setTableStyle { $0.fixedLayout = false; $0.width = nil; $0.widthPercent = nil }
        case .window: setTableStyle { $0.fixedLayout = false; $0.width = nil; $0.widthPercent = 100 }
        case .fixed: setTableStyle { $0.fixedLayout = true }
        }
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

    // MARK: Cell borders and shading

    /// The cells a table command works on: the selected block, else the
    /// bounding block of the cells the selection touches.
    public var targetCellBlock: CellBlock? {
        if let b = selection.block { return b }
        guard let here = currentCell else { return nil }
        var rows = here.row ... here.row + here.rowSpan - 1
        var cols = here.column ... here.column + here.span - 1
        for i in selection.start.paragraph ... selection.end.paragraph {
            guard let c = document.paragraphs[i].cell, c.table == here.table else { continue }
            rows = min(rows.lowerBound, c.row) ... max(rows.upperBound, c.row + c.rowSpan - 1)
            cols = min(cols.lowerBound, c.column) ... max(cols.upperBound, c.column + c.span - 1)
        }
        return CellBlock(table: here.table, rows: rows, columns: cols)
    }

    /// Apply `change` to every cell of the target block, one undo step,
    /// keeping the selection. Nothing is recorded when no cell changed.
    /// `outside`, when given, also sees every other cell of the table.
    private func _formatCells(_ change: (inout CellRef, CellBlock) -> Void, outside: ((inout CellRef, CellBlock) -> Void)? = nil) {
        guard let block = targetCellBlock, let range = currentTableRange else { return }
        let old = Array(document.paragraphs[range])
        var paras = old
        for i in paras.indices {
            guard var c = paras[i].cell, c.table == block.table else { continue }
            if block.contains(c) { change(&c, block) } else if let outside { outside(&c, block) } else { continue }
            paras[i].cell = c
        }
        guard paras != old else { return }
        let sel = selection
        edit {
            perform(.removeParagraphs(at: range.lowerBound, old))
            perform(.insertParagraphs(at: range.lowerBound, paras))
            selection = sel
        }
    }

    /// Shade the target cells (nil clears the shading), one undo step.
    /// `themeAttrs` (from `WordTheme.attrs`) keeps the shading following the document's theme in the file; the
    /// colour is what it resolves to now. A plain colour clears any earlier theme link.
    public func setCellShading(_ color: Color?, themeAttrs: String? = nil) {
        _formatCells { c, _ in c.fill = color; c.styleFilled = nil; c.fillThemeAttrs = color == nil ? nil : themeAttrs }
    }

    // MARK: Table properties (W-TB-3). Each is one undo step.

    /// Where the target cells' text stands between the cell's top and bottom: "top", "center" or "bottom".
    public func setCellVerticalAlignment(_ align: String) {
        guard ["top", "center", "bottom"].contains(align) else { return }
        _formatCells { c, _ in c.verticalAlign = align == "top" ? nil : align }
    }

    /// Word's nine Align buttons: where the target cells' text stands, across (the paragraphs' alignment) and
    /// down (the cell's), in one undo step.
    public func setCellAlignment(vertical: String, horizontal: ParagraphAlignment) {
        guard ["top", "center", "bottom"].contains(vertical), let block = targetCellBlock, let range = currentTableRange else { return }
        let old = Array(document.paragraphs[range])
        var paras = old
        for i in paras.indices {
            guard var c = paras[i].cell, block.contains(c) else { continue }
            c.verticalAlign = vertical == "top" ? nil : vertical
            paras[i].cell = c
            paras[i].style.alignment = horizontal
        }
        guard paras != old else { return }
        let sel = selection
        edit {
            perform(.removeParagraphs(at: range.lowerBound, old))
            perform(.insertParagraphs(at: range.lowerBound, paras))
            selection = sel
        }
    }

    /// The target cells' own margins in points (Word's `w:tcMar`), over the table's.
    public func setCellMargins(top: Double, left: Double, bottom: Double, right: Double) {
        let t = max(0, top), l = max(0, left), b = max(0, bottom), r = max(0, right)
        func tw(_ v: Double) -> Int { Int((v * 20).rounded()) }
        let xml = "<w:tcMar><w:top w:w=\"\(tw(t))\" w:type=\"dxa\"/><w:left w:w=\"\(tw(l))\" w:type=\"dxa\"/>"
            + "<w:bottom w:w=\"\(tw(b))\" w:type=\"dxa\"/><w:right w:w=\"\(tw(r))\" w:type=\"dxa\"/></w:tcMar>"
        _formatCells { c, _ in
            c.padding = EdgeInsets(left: l, top: t, right: r, bottom: b)
            c.marginsXML = xml
        }
    }

    /// The direction the target cells' text runs: across, or turned down or up.
    public func setCellTextDirection(_ direction: CellRef.CellTextDirection) {
        _formatCells { c, _ in
            guard c.textDirection != direction else { return }
            c.textDirection = direction
            c.textDirectionValue = nil
        }
    }

    /// The rows the selection touches (the caret's row when nothing is selected as a block).
    public var targetRows: ClosedRange<Int>? {
        if let b = targetCellBlock { return b.rows }
        return currentCell.map { $0.row...($0.row + $0.rowSpan - 1) }
    }

    /// The table's width: points, a percent of the text width, or nil for automatic.
    /// The columns are scaled to the new width in the same undo step, so each cell's preferred width (written from them)
    /// agrees with the table's: Word opened an 80% table whose cells still asked for the full text width (lab tb3).
    /// `textWidth` is the page's text width, what a percent is of.
    public func setTableWidth(points: Double? = nil, percent: Double? = nil, textWidth: Double = PageSetup.letter.contentWidth) {
        guard let t = currentCell?.table else { return }
        let old = document.tableStyles[t]
        var new = old ?? TableStyle()
        new.width = points.map { max(1, $0) }
        new.widthPercent = percent.map { min(600, max(1, $0)) }
        let target = new.width ?? new.widthPercent.map { textWidth * $0 / 100 }
        let oldCols = document.tableColumns[t]
        var cols = oldCols
        // A table with no columns of its own is saved with equal ones across the text width: give it equal ones across
        // the new width instead.
        let count = document.paragraphs.compactMap { $0.cell?.table == t ? $0.cell!.column + $0.cell!.span : nil }.max() ?? 0
        if let target, count > 0 {
            let c = oldCols?.count == count ? oldCols! : Array(repeating: textWidth / Double(count), count: count)
            let sum = c.reduce(0, +)
            if sum > 0, abs(sum - target) > 0.01 || oldCols == nil { cols = c.map { $0 * target / sum } }
        }
        guard new != (old ?? TableStyle()) || cols != oldCols else { return }
        edit {
            if new != (old ?? TableStyle()) { perform(.setTableStyle(t, old: old, new: new == TableStyle() ? nil : new)) }
            if cols != oldCols { perform(.setTableColumns(t, old: oldCols, new: cols)) }
        }
    }

    /// Automatic column widths (the grid fits its text) or fixed ones.
    public func setTableAutofit(_ autofit: Bool) { setTableStyle { $0.fixedLayout = !autofit } }

    public func setTableAlignment(_ alignment: ParagraphAlignment) { setTableStyle { $0.alignment = alignment } }

    /// How far the table's left edge stands in from the margin, in points (negative stands out).
    public func setTableIndent(_ points: Double) { setTableStyle { $0.indent = points } }

    /// The default margins inside every cell of the table, in points; nil leaves a side as it was.
    public func setTableCellMargins(top: Double? = nil, left: Double? = nil, bottom: Double? = nil, right: Double? = nil) {
        setTableStyle {
            if let v = top { $0.cellMarginTop = max(0, v) }
            if let v = left { $0.cellMarginLeft = max(0, v) }
            if let v = bottom { $0.cellMarginBottom = max(0, v) }
            if let v = right { $0.cellMarginRight = max(0, v) }
        }
    }

    /// A least (or, `exact`, a fixed) height for the target rows, in points; nil clears it.
    public func setRowHeight(_ points: Double?, exact: Bool = false) {
        guard let rows = targetRows else { return }
        setTableStyle { t in
            for r in rows {
                if let h = points {
                    t.rowHeights[r] = max(1, h)
                    if exact { t.rowsExactHeight.insert(r) } else { t.rowsExactHeight.remove(r) }
                } else {
                    t.rowHeights[r] = nil
                    t.rowsExactHeight.remove(r)
                }
            }
        }
    }

    /// Dragging a row's bottom border: that row gets at least `points` of height (kept exact if it already was), one undo.
    public func setRowHeight(table: String, row: Int, points: Double) {
        setTableStyle(of: table) { $0.rowHeights[row] = max(1, points) }
    }

    /// Whether the target rows may split across a page.
    public func setRowsMayBreak(_ mayBreak: Bool) {
        guard let rows = targetRows else { return }
        setTableStyle { t in for r in rows { if mayBreak { t.rowsCantSplit.remove(r) } else { t.rowsCantSplit.insert(r) } } }
    }

    /// The first `count` rows repeat at the head of each page the table runs onto; 0 turns it off.
    public func setRepeatedHeaderRows(_ count: Int) {
        setTableStyle { $0.headerRow = count > 0; if count > 0 { $0.headerRowCount = count } }
    }

    /// Draw or clear lines on sides of the target cells, one undo step.
    /// `top`, `bottom`, `left`, `right` are the block's outer sides;
    /// `insideH` and `insideV` the lines between its cells. A line with
    /// style "none" removes the line; a side not named is left alone.
    public func setCellBorders(_ lines: [CellSide: CellBorderLine]) {
        guard !lines.isEmpty else { return }
        let borders = currentCell.flatMap { document.tableStyles[$0.table]?.borders } ?? true
        _formatCells({ c, block in
            let lastRow = c.row + c.rowSpan - 1, lastCol = c.column + c.span - 1
            var apply: [String: CellBorderLine] = [:]
            for (side, line) in lines {
                switch side {
                case .top: if c.row == block.rows.lowerBound { apply["top"] = line }
                case .bottom: if lastRow == block.rows.upperBound { apply["bottom"] = line }
                case .left: if c.column == block.columns.lowerBound { apply["left"] = line }
                case .right: if lastCol == block.columns.upperBound { apply["right"] = line }
                case .insideH:
                    if lastRow < block.rows.upperBound { apply["bottom"] = line }
                    if c.row > block.rows.lowerBound { apply["top"] = line }
                case .insideV:
                    if lastCol < block.columns.upperBound { apply["right"] = line }
                    if c.column > block.columns.lowerBound { apply["left"] = line }
                }
            }
            Self._applyCellSides(&c, apply, borders)
        }, outside: { c, block in
            // Word sets the facing side of a cell across the block's edge
            // too, so a cleared edge is not drawn by the neighbour.
            let lastRow = c.row + c.rowSpan - 1, lastCol = c.column + c.span - 1
            let rows = c.row <= block.rows.upperBound && lastRow >= block.rows.lowerBound
            let cols = c.column <= block.columns.upperBound && lastCol >= block.columns.lowerBound
            var apply: [String: CellBorderLine] = [:]
            if cols, c.row == block.rows.upperBound + 1, let l = lines[.bottom] { apply["top"] = l }
            if cols, lastRow == block.rows.lowerBound - 1, let l = lines[.top] { apply["bottom"] = l }
            if rows, c.column == block.columns.upperBound + 1, let l = lines[.right] { apply["left"] = l }
            if rows, lastCol == block.columns.lowerBound - 1, let l = lines[.left] { apply["right"] = l }
            Self._applyCellSides(&c, apply, borders)
        })
    }

    /// Set the named sides of one cell's borders and its drawn edges.
    static func _applyCellSides(_ c: inout CellRef, _ apply: [String: CellBorderLine], _ borders: Bool) {
        guard !apply.isEmpty else { return }
        c.bordersXML = _mergeCellSides(c.bordersXML ?? c.rowBordersXML, apply)
        c.bordersKeptUnder = borders
        var e = c.edges ?? BorderEdges()
        for (name, line) in apply {
            let on: Bool? = line.style == "none" ? false : true
            switch name {
            case "top": e.top = on
            case "left": e.left = on
            case "bottom": e.bottom = on
            default: e.right = on
            }
        }
        c.edges = e
        // A cell merged downward draws its bottom from its last row's cell.
        if c.rowSpan > 1, let b = apply["bottom"] {
            var cont = c.continuationBordersXML
            while cont.count < c.rowSpan - 1 { cont.append(nil) }
            cont[c.rowSpan - 2] = _mergeCellSides(cont[c.rowSpan - 2], ["bottom": b])
            c.continuationBordersXML = cont
        }
    }

    /// `xml` (a `w:tcBorders`, or nil) with the named sides replaced, the
    /// sides it had and are not named kept, in the schema's order.
    static func _mergeCellSides(_ xml: String?, _ apply: [String: CellBorderLine]) -> String {
        let order = ["top", "left", "start", "bottom", "right", "end", "insideH", "insideV", "tl2br", "tr2bl"]
        var out = "<w:tcBorders>"
        for name in order {
            if let line = apply[name] { out += line.xml(name); continue }
            guard let xml, let a = xml.firstRange(of: "<w:\(name) ") else { continue }
            let rest = xml[a.lowerBound...]
            guard let gt = rest.firstRange(of: ">") else { continue }
            let selfClosed = rest[..<gt.lowerBound].hasSuffix("/")
            if selfClosed { out += rest[..<gt.upperBound] }
            else if let end = rest.firstRange(of: "</w:\(name)>") { out += rest[..<end.upperBound] }
        }
        return out + "</w:tcBorders>"
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

    /// Word's Split Cells: the caret's cell becomes `columns` x `rows` cells,
    /// one undo step. A cell with fewer grid columns (or rows) than asked
    /// makes the grid wider (taller): the cells across the new columns widen
    /// (or grow taller) to keep their place, and the column widths of the
    /// split cell are shared evenly. The text stays in the first piece.
    /// Returns false when nothing was split.
    @discardableResult
    public func splitCell(columns n: Int, rows m: Int, columnFraction: Double? = nil) -> Bool {
        guard let here = currentCell, n >= 1, m >= 1, n * m > 1, n <= 63, m <= 200 else { return false }
        let s = here.span, q = here.rowSpan
        let rowExtra = max(0, m - q)
        let e = here.column + s, r1 = here.row + q - 1
        let cols = document.columnCount(of: here.table)
        var widths = document.tableColumns[here.table]
        if widths?.count != cols { widths = nil }
        // The split cell's width is cut into n EQUAL pieces. Every old gridline stays; a new
        // gridline is added wherever a cut falls between two of them, and every cell is
        // renumbered through the new grid.
        let w0 = widths ?? Array(repeating: 468.0 / Double(cols), count: cols)
        var x: [Double] = [0]
        for v in w0 { x.append(x.last! + v) }
        let x0 = x[here.column], x1 = x[e]
        var newX = x
        for j in 1 ..< n {
            let t = x0 + (x1 - x0) * (n == 2 ? (columnFraction ?? 0.5) : Double(j) / Double(n))
            if !newX.contains(where: { abs($0 - t) < 0.5 }) { newX.append(t) }
        }
        newX.sort()
        func gridIndex(_ pos: Double) -> Int {
            newX.indices.min { abs(newX[$0] - pos) < abs(newX[$1] - pos) }!
        }
        let newCols = newX.count - 1
        let colExtra = newCols - cols
        guard newCols <= 63 else { return false }
        let oldIndex = x.map { gridIndex($0) }
        let cuts = (0 ... n).map { gridIndex(n == 2 && $0 == 1 ? x0 + (x1 - x0) * (columnFraction ?? 0.5) : x0 + (x1 - x0) * Double($0) / Double(n)) }
        guard (0 ..< n).allSatisfy({ cuts[$0 + 1] > cuts[$0] }) else { return false }
        if colExtra > 0 { widths = (0 ..< newCols).map { newX[$0 + 1] - newX[$0] } }
        let newWidths = widths
        let style = document.tableStyles[here.table]
        func pieces(_ total: Int, _ k: Int) -> [Int] {
            (0 ..< k).map { total / k + ($0 < total % k ? 1 : 0) }
        }
        let rowSizes = pieces(max(q, m), m)
        var caretAt: Int? = nil
        edit {
            _rewriteTable(caret: { _ in caretAt }, rewrite: { paras in
                var out: [RichParagraph] = []
                var extra: [CellRef] = []
                for var p in paras {
                    guard var c = p.cell else { out.append(p); continue }
                    if c.sameCell(as: here) {
                        if caretAt == nil {
                            caretAt = out.count
                            // The empty pieces, once, at the first paragraph.
                            for i in 0 ..< m {
                                for j in 0 ..< n where i + j > 0 {
                                    var d = here
                                    d.row = here.row + rowSizes[..<i].reduce(0, +)
                                    d.column = cuts[j]
                                    d.span = cuts[j + 1] - cuts[j]; d.rowSpan = rowSizes[i]
                                    extra.append(d)
                                }
                            }
                        }
                        c.column = cuts[0]; c.span = cuts[1] - cuts[0]; c.rowSpan = rowSizes[0]
                        p.cell = c
                        out.append(p)
                        continue
                    }
                    if colExtra != 0 {
                        let from = oldIndex[c.column], to = oldIndex[c.column + c.span]
                        c.column = from; c.span = to - from
                    }
                    if rowExtra > 0 {
                        if c.row > r1 { c.row += rowExtra }
                        else if c.row + c.rowSpan - 1 >= r1 { c.rowSpan += rowExtra }
                    }
                    p.cell = c
                    out.append(p)
                }
                // Each empty piece goes in reading order among the cells.
                for d in extra {
                    var e = RichParagraph(style: .cell)
                    e.cell = d
                    let at = out.firstIndex { q in
                        guard let c = q.cell, c.table == d.table else { return false }
                        return c.row > d.row || (c.row == d.row && c.column > d.column)
                    } ?? out.count
                    out.insert(e, at: at)
                }
                paras = out
            })
            if let w = newWidths, w != document.tableColumns[here.table] {
                perform(.setTableColumns(here.table, old: document.tableColumns[here.table], new: w))
            }
            if rowExtra > 0, var st = style, !(st.rowHeights.isEmpty && st.rowsCantSplit.isEmpty) {
                st.rowHeights = Dictionary(uniqueKeysWithValues: st.rowHeights.map { ($0.key > r1 ? $0.key + rowExtra : $0.key, $0.value) })
                st.rowsCantSplit = Set(st.rowsCantSplit.map { $0 > r1 ? $0 + rowExtra : $0 })
                perform(.setTableStyle(here.table, old: style, new: st))
            }
        }
        return true
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

    // MARK: Selecting parts of a table

    /// Select the cells of `rows` x `columns` in the caret's table (the
    /// corner cells become anchor and focus, so the block selection and
    /// every command that works on one follow).
    private func _selectCells(rows: (Int) -> ClosedRange<Int>, columns: (Int) -> ClosedRange<Int>) {
        guard let here = currentCell else { return }
        let members = document.paragraphs(inTable: here.table)
        let cells = members.compactMap { i in document.paragraphs[i].cell.map { (i, $0) } }
        let maxRow = cells.map { $0.1.row + $0.1.rowSpan - 1 }.max() ?? 0
        let maxCol = cells.map { $0.1.column + $0.1.span - 1 }.max() ?? 0
        let r = rows(maxRow), k = columns(maxCol)
        func paragraph(row: Int, column: Int) -> Int? {
            cells.first { $0.1.intersects(rows: row ... row, columns: column ... column) }?.0
        }
        guard let a = paragraph(row: r.lowerBound, column: k.lowerBound),
              let f = paragraph(row: r.upperBound, column: k.upperBound) else { return }
        moveTo(RichPosition(paragraph: a, offset: 0), extend: false)
        moveTo(RichPosition(paragraph: f, offset: 0), extend: true)
    }

    /// Select the whole row the caret is in.
    public func selectRow() {
        guard let here = currentCell else { return }
        let rows = here.row ... here.row + here.rowSpan - 1
        _selectCells(rows: { _ in rows }, columns: { 0 ... $0 })
    }

    /// Select the whole column the caret is in.
    public func selectColumn() {
        guard let here = currentCell else { return }
        let cols = here.column ... here.column + here.span - 1
        _selectCells(rows: { 0 ... $0 }, columns: { _ in cols })
    }

    /// Select every cell of the caret's table.
    public func selectTable() {
        _selectCells(rows: { 0 ... $0 }, columns: { 0 ... $0 })
    }

    /// Select every cell of `table` wherever the caret is (its move handle was clicked).
    public func selectTable(_ table: String) {
        guard let i = document.paragraphs.firstIndex(where: { $0.cell?.table == table }) else { return }
        moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
        selectTable()
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

    // MARK: Page setup

    /// The paragraph that ends the section holding `paragraph` (a section's
    /// mark carries its page), or -1 for the last section.
    public func sectionMark(containing paragraph: Int) -> Int {
        var i = max(0, paragraph)
        while i < document.paragraphs.count - 1 {
            let p = document.paragraphs[i]
            if p.cell == nil, p.style.sectionPage != nil { return i }
            i += 1
        }
        return -1
    }

    /// Set the page of the section holding `paragraph` (default: the
    /// caret's), as one undoable step. `lastSetup` is the last section's
    /// current page (the session's) for when the section is the last.
    public func setPageSetup(_ new: PageSetup, lastSetup: PageSetup, paragraph: Int? = nil) {
        let mark = sectionMark(containing: paragraph ?? selection.focus.paragraph)
        let old = mark < 0 ? (document.lastSectionPage ?? lastSetup) : document.paragraphs[mark].style.sectionPage
        // (`new` is the paper's page; a vertical section keeps the turned one.)
        let new = new.vertical ? new.transposed() : new
        guard old != new else { return }
        edit { perform(.setSectionPage(mark, old: old, new: new)) }
    }

    /// W-PG-1: change the page of the caret's section, or of every section, by editing a copy of each one's own
    /// setup (so a section keeps its columns, title page and the rest). One undo step.
    public struct PageOptions: Equatable, Sendable {
        public var titlePage: Bool, evenAndOdd: Bool, pageNumberStart: Int?
        /// The page numbers' `w:fmt` (nil: the file names none, so decimal).
        public var pageNumberFormat: String?
        /// The chapter number before the page number: the heading level whose number it is (`w:chapStyle`; nil: none)
        /// and the character between them (`w:chapSep`; nil: hyphen).
        public var chapterStyle: Int?, chapterSeparator: String?
        public init(titlePage: Bool, evenAndOdd: Bool, pageNumberStart: Int?, pageNumberFormat: String? = nil,
                    chapterStyle: Int? = nil, chapterSeparator: String? = nil) {
            self.titlePage = titlePage; self.evenAndOdd = evenAndOdd; self.pageNumberStart = pageNumberStart; self.pageNumberFormat = pageNumberFormat
            self.chapterStyle = chapterStyle; self.chapterSeparator = chapterSeparator
        }
        /// These options with the document-wide odd and even setting replaced.
        func with(evenAndOdd: Bool) -> PageOptions { var o = self; o.evenAndOdd = evenAndOdd; return o }
        /// A section's page with these section options.
        func applied(to page: PageSetup) -> PageSetup {
            var s = page
            s.titlePage = titlePage; s.pageNumberStart = pageNumberStart; s.pageNumberFormat = pageNumberFormat
            s.chapterStyle = chapterStyle; s.chapterSeparator = chapterSeparator
            return s
        }
    }
    /// The page options of the section holding the caret (`allSections: false`) as the Layout tab shows them.
    public func pageOptions(sectionMark mark: Int) -> PageOptions {
        if mark < 0 { return PageOptions(titlePage: document.titlePage, evenAndOdd: document.evenAndOddHeaders, pageNumberStart: document.pageNumberStart,
                                      pageNumberFormat: document.pageNumberFormat, chapterStyle: document.chapterStyle,
                                      chapterSeparator: document.chapterSeparator) }
        let s = document.paragraphs[mark].style.sectionPage
        return PageOptions(titlePage: s?.titlePage ?? false, evenAndOdd: document.evenAndOddHeaders, pageNumberStart: s?.pageNumberStart,
                           pageNumberFormat: s?.pageNumberFormat, chapterStyle: s?.chapterStyle, chapterSeparator: s?.chapterSeparator)
    }
    /// W-HF-2: different first page and first page number for the caret's section (every section with
    /// `allSections`), and different odd and even pages for the document. One undo step.
    public func changePageOptions(allSections: Bool, _ new: PageOptions, lastSetup: PageSetup) {
        var marks: [Int] = []
        if allSections {
            for i in 0..<document.paragraphs.count where document.paragraphs[i].cell == nil && document.paragraphs[i].style.sectionPage != nil { marks.append(i) }
            marks.append(-1)
        } else { marks = [sectionMark(containing: selection.focus.paragraph)] }
        edit {
            for mark in marks {
                if mark < 0 {
                    let old = pageOptions(sectionMark: -1)
                    let next = new
                    if next != old { perform(.setPageOptions(old: old, new: next)) }
                } else if let old = document.paragraphs[mark].style.sectionPage {
                    let s = new.applied(to: old)
                    if s != old { perform(.setSectionPage(mark, old: old, new: s)) }
                }
            }
            if document.evenAndOddHeaders != new.evenAndOdd {
                let old = pageOptions(sectionMark: -1)
                perform(.setPageOptions(old: old, new: old.with(evenAndOdd: new.evenAndOdd)))
            }
        }
    }

    /// The section marks in order (the paragraphs that end a section, as the layout counts them), then -1 for the last.
    func sectionMarks() -> [Int] {
        var marks: [Int] = []
        for i in 0..<max(0, document.paragraphs.count - 1) where document.paragraphs[i].cell == nil && document.paragraphs[i].style.sectionPage != nil { marks.append(i) }
        return marks + [-1]
    }
    /// The `w:headerReference`/`w:footerReference` elements of `kind` and `type` in a kept `w:sectPr`, as ranges,
    /// with the `r:id` each names. (A reference with no `w:type` is the default one, as the reader takes it.)
    static func _references(in xml: String, kind: KeptHeaderFooter.Kind, type: String) -> [(range: Range<String.Index>, id: String?)] {
        let tag = kind == .header ? "<w:headerReference" : "<w:footerReference"
        var found: [(Range<String.Index>, String?)] = []
        var from = xml.startIndex
        while let r = xml.rangeOfSubstring(tag, in: from..<xml.endIndex) {
            guard let close = xml.rangeOfSubstring(">", in: r.upperBound..<xml.endIndex) else { break }
            from = close.upperBound
            let next = xml[r.upperBound...].first
            guard next == " " || next == "/" || next == ">" else { continue }
            var end = close.upperBound
            if xml[xml.index(before: close.lowerBound)] != "/", let shut = xml.rangeOfSubstring("</" + tag.dropFirst() + ">", in: end..<xml.endIndex) {
                end = shut.upperBound
            }
            let element = String(xml[r.lowerBound..<close.upperBound])
            func attr(_ name: String) -> String? {
                guard let a = element.rangeOfSubstring(" \(name)=\""), let q = element.rangeOfSubstring("\"", in: a.upperBound..<element.endIndex) else { return nil }
                return String(element[a.upperBound..<q.lowerBound])
            }
            let t = attr("w:type").map { $0 == "odd" ? "default" : $0 } ?? "default"
            if t == type { found.append((r.lowerBound..<end, attr("r:id"))) }
            from = end
        }
        return found
    }
    /// Whether a section names its own header (or footer) of `type`: the last section by its kept parts and,
    /// for the default one, by the text the editor writes as a part of its own.
    func ownsHeaderFooter(sectionMark mark: Int, kind: KeptHeaderFooter.Kind, type: String) -> Bool {
        if mark >= 0 { return !Self._references(in: document.paragraphs[mark].style.sectionXML ?? "", kind: kind, type: type).isEmpty }
        if document.keptHeaderFooters.contains(where: { $0.kind == kind && $0.type == type }) { return true }
        return type == "default" && !(kind == .header ? document.header : document.footer).isEmpty
    }
    /// W-HF-2 Link to Previous: true when the section holding `paragraph` shows the header (or footer) of `type` of the
    /// section before it, having none of its own; nil for the first section, which has nothing to link to.
    public func linkedToPrevious(paragraph: Int? = nil, kind: KeptHeaderFooter.Kind, type: String = "default") -> Bool? {
        let mark = sectionMark(containing: paragraph ?? selection.focus.paragraph)
        let marks = sectionMarks()
        guard let s = marks.firstIndex(of: mark), s > 0 else { return nil }
        return !ownsHeaderFooter(sectionMark: mark, kind: kind, type: type)
    }
    /// The part the section before `marks[s]` shows for `kind` and `type`: its own reference's relationship, or the
    /// one it has from the section before it.
    func previousReference(_ marks: [Int], _ s: Int, kind: KeptHeaderFooter.Kind, type: String) -> KeptRel? {
        var t = s - 1
        while t >= 0 {
            let style = document.paragraphs[marks[t]].style
            if let id = Self._references(in: style.sectionXML ?? "", kind: kind, type: type).first?.id,
               let rel = style.sectionRels.first(where: { $0.id == id && !$0.external }) { return rel }
            t -= 1
        }
        return nil
    }
    /// A relationship target as a package path ("header2.xml" from word/document.xml is "word/header2.xml").
    static func _packagePath(_ target: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        var comps = ["word"]
        for c in target.split(separator: "/") {
            if c == ".." { if !comps.isEmpty { comps.removeLast() } } else if c != "." { comps.append(String(c)) }
        }
        return comps.joined(separator: "/")
    }
    /// W-HF-2 Link to Previous, as Word's button: linking drops the section's own reference, so its pages show the
    /// section before's header (or footer), and so do the following sections that had theirs from it; unlinking
    /// gives it a reference of its own to the part it showed, so its pages look the same until it is edited. One undo step.
    /// Returns false where there is nothing to do (the first section, already so, or no part to name).
    @discardableResult
    public func setLinkToPrevious(_ linked: Bool, paragraph: Int? = nil, kind: KeptHeaderFooter.Kind, type: String = "default") -> Bool {
        let mark = sectionMark(containing: paragraph ?? selection.focus.paragraph)
        let marks = sectionMarks()
        guard let s = marks.firstIndex(of: mark), s > 0, ownsHeaderFooter(sectionMark: mark, kind: kind, type: type) == linked else { return false }
        if !linked {
            guard let rel = previousReference(marks, s, kind: kind, type: type) else { return false }
            let element = "<w:\(kind == .header ? "headerReference" : "footerReference") w:type=\"\(type)\" r:id=\"\(rel.id)\"/>"
            if mark >= 0 {
                var style = document.paragraphs[mark].style
                guard var xml = style.sectionXML, let open = xml.rangeOfSubstring("<w:sectPr"),
                      let close = xml.rangeOfSubstring(">", in: open.upperBound..<xml.endIndex) else { return false }
                if xml[xml.index(before: close.lowerBound)] == "/" {
                    xml.replaceSubrange(xml.index(before: close.lowerBound)..<close.upperBound, with: ">" + element + "</w:sectPr>")
                } else {
                    xml.insert(contentsOf: element, at: close.upperBound)
                }
                style.sectionXML = xml
                if !style.sectionRels.contains(where: { $0.id == rel.id }) { style.sectionRels.append(rel) }
                let old = document.paragraphs[mark].style
                edit { perform(.setParagraphStyle(mark, old: old, new: style)) }
            } else {
                let path = Self._packagePath(rel.target)
                guard document.keptParts[path] != nil else { return false }
                let text = type == "default" ? (kind == .header ? document.header : document.footer) : ""
                let old = document.keptHeaderFooters
                edit { perform(.setKeptHeaderFooters(old: old, new: old + [KeptHeaderFooter(kind: kind, type: type, part: path, text: text)])) }
            }
            return true
        }
        // Linking: the following sections that had theirs from this one show the previous one's from now on.
        var follow = [s]
        var t = s + 1
        while t < marks.count, !ownsHeaderFooter(sectionMark: marks[t], kind: kind, type: type) { follow.append(t); t += 1 }
        let oldHF = document.headerFooters
        var newHF = oldHF
        if oldHF.contains(where: { $0.section != nil }) {
            let shown = oldHF.first { $0.kind == kind && $0.type == type && $0.section == s - 1 }
            newHF.removeAll { $0.kind == kind && $0.type == type && $0.section.map(follow.contains) == true }
            if let shown { for t in follow { var e = shown; e.section = t; e.edited = nil; newHF.append(e) } }
        }
        var header = document.header, footer = document.footer
        if mark < 0, type == "default" {
            if kind == .header { header = "" } else { footer = "" }
            newHF.removeAll { $0.kind == kind && $0.type == "default" && $0.section == nil && $0.edited == true }
        }
        edit {
            if mark >= 0 {
                let old = document.paragraphs[mark].style
                var style = old
                var xml = style.sectionXML ?? ""
                let refs = Self._references(in: xml, kind: kind, type: type)
                for r in refs.reversed() { xml.removeSubrange(r.range) }
                style.sectionXML = xml
                style.sectionRels.removeAll { rel in refs.contains { $0.id == rel.id } && !xml.containsSubstring("\"\(rel.id)\"") }
                perform(.setParagraphStyle(mark, old: old, new: style))
            } else {
                let old = document.keptHeaderFooters
                let new = old.filter { !($0.kind == kind && $0.type == type) }
                if new != old { perform(.setKeptHeaderFooters(old: old, new: new)) }
            }
            if newHF != oldHF || header != document.header || footer != document.footer {
                perform(.setRichHeaderFooter(new: newHF, old: oldHF, header: header, footer: footer, oldHeader: document.header, oldFooter: document.footer))
            }
        }
        return true
    }

    public func changePageSetup(allSections: Bool, lastSetup: PageSetup, _ change: (inout PageSetup) -> Void) {
        var marks: [Int] = []
        if allSections {
            for i in 0..<document.paragraphs.count where document.paragraphs[i].cell == nil && document.paragraphs[i].style.sectionPage != nil { marks.append(i) }
            marks.append(-1)
        } else {
            marks = [sectionMark(containing: selection.focus.paragraph)]
        }
        var steps: [(Int, PageSetup, PageSetup)] = []
        for mark in marks {
            let old = mark < 0 ? (document.lastSectionPage ?? lastSetup) : document.paragraphs[mark].style.sectionPage!
            var new = old.physical
            change(&new)
            if new.vertical { new = new.transposed() }
            if new != old { steps.append((mark, old, new)) }
        }
        guard !steps.isEmpty else { return }
        edit { for (mark, old, new) in steps { perform(.setSectionPage(mark, old: old, new: new)) } }
    }

    // MARK: Header and footer

    /// Sets the header and footer text. A side whose file part holds more than
    /// plain text (see `hasRichHeaderFooter`) is left alone, and named in the
    /// result, so the caller can say so: the strip must not flatten it.
    @discardableResult
    public func setHeaderFooter(header: String? = nil, footer: String? = nil) -> [KeptHeaderFooter.Kind] {
        var kept: [KeptHeaderFooter.Kind] = []
        var newHeader = header ?? document.header
        var newFooter = footer ?? document.footer
        if newHeader != document.header, document.hasRichHeaderFooter(.header) { newHeader = document.header; kept.append(.header) }
        if newFooter != document.footer, document.hasRichHeaderFooter(.footer) { newFooter = document.footer; kept.append(.footer) }
        guard newHeader != document.header || newFooter != document.footer else { return kept }
        edit {
            perform(.setHeaderFooter(header: newHeader, footer: newFooter,
                                     oldHeader: document.header, oldFooter: document.footer))
        }
        return kept
    }

    /// W-HF-1: the default header or footer as formatted paragraphs (bold, italic, size, colour, font, alignment,
    /// tabs, page fields). One undo step; the save writes a part from them. Pictures and tables are not carried
    /// (use `hasRichHeaderFooter` to refuse those first).
    public func setRichHeaderFooter(_ kind: KeptHeaderFooter.Kind, paragraphs: [RichParagraph]) {
        let paras = paragraphs.isEmpty ? [RichParagraph()] : paragraphs
        var all = document.headerFooters
        var entry = RichHeaderFooter(kind: kind, type: "default", paragraphs: paras)
        entry.edited = true
        if let i = all.firstIndex(where: { $0.kind == kind && $0.type == "default" && $0.section == nil }) { entry.section = nil; all[i] = entry }
        else { all.append(entry) }
        let plain = paras.map { $0.text }.joined(separator: " ")
        guard all != document.headerFooters else { return }
        edit {
            perform(.setRichHeaderFooter(new: all, old: document.headerFooters,
                                         header: kind == .header ? plain : document.header, footer: kind == .footer ? plain : document.footer,
                                         oldHeader: document.header, oldFooter: document.footer))
        }
    }

    /// W-HF-1 PR 2: how the strip shows one side's line.
    public struct HeaderFooterLook: Equatable, Sendable {
        public var bold = false
        public var italic = false
        public var alignment: ParagraphAlignment = .left
        public init(bold: Bool = false, italic: Bool = false, alignment: ParagraphAlignment = .left) {
            self.bold = bold; self.italic = italic; self.alignment = alignment
        }
        public var isDefault: Bool { self == HeaderFooterLook() }
    }

    /// The look of the file's edited default header or footer (first paragraph, first run), else plain.
    public func headerFooterLook(_ kind: KeptHeaderFooter.Kind) -> HeaderFooterLook {
        guard let e = document.headerFooters.first(where: { $0.kind == kind && $0.type == "default" && $0.section == nil && $0.edited == true }),
              let p = e.paragraphs.first else { return HeaderFooterLook() }
        let st = p.runs.first?.style
        return HeaderFooterLook(bold: st?.bold ?? false, italic: st?.italic ?? false, alignment: p.style.alignment)
    }

    /// A strip line ("Report {PAGE}") as one paragraph: the page fields become field runs, the look applies to all.
    public static func headerFooterParagraph(template: String, look: HeaderFooterLook) -> RichParagraph {
        var text = ""
        var runs: [Run] = []
        var plain = CharStyle.plain
        plain.bold = look.bold; plain.italic = look.italic
        var rest = Substring(template)
        func emit(_ s: String, _ st: CharStyle) {
            guard !s.isEmpty else { return }
            text += s
            runs.append(Run(length: s.utf16.count, style: st))
        }
        while !rest.isEmpty {
            var hit: (Range<Substring.Index>, String, String)? = nil
            for (token, instr, shown) in [(RichDocument.pageField, "PAGE", "1"), (RichDocument.pageCountField, "NUMPAGES", "1")] {
                if let r = rest.rangeOfSubstring(token), hit == nil || r.lowerBound < hit!.0.lowerBound { hit = (r, instr, shown) }
            }
            guard let h = hit else { emit(String(rest), plain); break }
            emit(String(rest[rest.startIndex..<h.0.lowerBound]), plain)
            var f = plain; f.field = h.1
            emit(h.2, f)
            rest = rest[h.0.upperBound...]
        }
        var para = RichParagraph(text: text, runs: runs.isEmpty ? nil : runs)
        para.style.alignment = look.alignment
        return para
    }

    /// Done in the strip: a plain line keeps the old plain path; a formatted one becomes a rich part.
    public func applyHeaderFooterStrip(header: String, footer: String, headerLook: HeaderFooterLook, footerLook: HeaderFooterLook,
                                       headerLocked: Bool, footerLocked: Bool) {
        let hOld = headerFooterLook(.header), fOld = headerFooterLook(.footer)
        let hRich = !headerLocked && (!headerLook.isDefault || !hOld.isDefault)
        let fRich = !footerLocked && (!footerLook.isDefault || !fOld.isDefault)
        if !hRich && !fRich {
            _ = setHeaderFooter(header: header, footer: footer); return
        }
        edit {
            if hRich { setRichHeaderFooter(.header, paragraphs: [Self.headerFooterParagraph(template: header, look: headerLook)]) }
            else if !headerLocked { _ = setHeaderFooter(header: header, footer: document.footer) }
            if fRich { setRichHeaderFooter(.footer, paragraphs: [Self.headerFooterParagraph(template: footer, look: footerLook)]) }
            else if !footerLocked { _ = setHeaderFooter(header: document.header, footer: footer) }
        }
    }

    /// Word's Page Number: a centred "n" in the footer, or none.
    @discardableResult
    public func togglePageNumbers() -> Bool {
        let field = "Page \(RichDocument.pageField) of \(RichDocument.pageCountField)"
        return setHeaderFooter(footer: document.footer.containsSubstring(RichDocument.pageField) ? "" : field).isEmpty
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
            // Clamped: the wrap-around pass asks for the caret's offset
            // plus the query's length, which runs past the end of a
            // paragraph the caret sits near the end of.
            let length = text.utf16.count
            let a = lo.map { String.Index(utf16Offset: min(max($0, 0), length), in: text) } ?? text.startIndex
            let b = hi.map { String.Index(utf16Offset: min(max($0, 0), length), in: text) } ?? text.endIndex
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
                    let at = lo + _deleteRange(in: i, lo ..< hi)  // tracked: the old text stays, deleted, before the new
                    if !replacement.isEmpty {
                        perform(.insertText(RichPosition(paragraph: i, offset: at), replacement,
                                            [Run(length: replacement.utf16.count, style: _typed(style))]))
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

    // MARK: Find with a pattern (U-FR-1: match case, whole word, wildcards, regex)

    /// The next match of `pattern` after the caret (before it when `backwards`), wrapping; nil when none.
    public func find(_ pattern: TextPattern, backwards: Bool = false) -> RichSelection? {
        let start = document.clamped(backwards ? selection.start : selection.end)
        let n = document.paragraphs.count
        func hit(_ i: Int, from: Int?, back: Bool) -> RichSelection? {
            let text = document.paragraphs[i].text
            let at = from.map { String.Index(utf16Offset: min(max($0, 0), text.utf16.count), in: text) }
                ?? (back ? text.endIndex : text.startIndex)
            guard let m = pattern.firstMatch(in: text, from: at, backwards: back) else { return nil }
            return RichSelection(
                anchor: RichPosition(paragraph: i, offset: m.range.lowerBound.utf16Offset(in: text)),
                focus: RichPosition(paragraph: i, offset: m.range.upperBound.utf16Offset(in: text)))
        }
        if let s = hit(start.paragraph, from: start.offset, back: backwards) { return s }
        for k in 1 ..< max(n, 1) {
            let i = backwards ? (start.paragraph - k + n * 2) % n : (start.paragraph + k) % n
            if let s = hit(i, from: nil, back: backwards) { return s }
        }
        return hit(start.paragraph, from: nil, back: backwards)
    }

    /// Which match the selection is, and how many there are ("3 of 12"); nil when the selection is not a match.
    public func matchPosition(_ pattern: TextPattern) -> (index: Int, total: Int)? {
        var total = 0, index: Int?
        let sel = selection
        for (i, p) in document.paragraphs.enumerated() {
            let text = p.text
            for m in pattern.matches(in: text) {
                total += 1
                if index == nil, i == sel.start.paragraph, sel.start.paragraph == sel.end.paragraph,
                   m.range.lowerBound.utf16Offset(in: text) == sel.start.offset { index = total }
            }
        }
        return index.map { ($0, total) }
    }

    /// Replace the selection when it is exactly one match of `pattern`; one undo step. False when it is not.
    @discardableResult
    public func replaceSelection(_ pattern: TextPattern, with template: String) -> Bool {
        let sel = selection
        guard sel.anchor.paragraph == sel.focus.paragraph, sel.anchor != sel.focus else { return false }
        let i = sel.start.paragraph
        let text = document.paragraphs[i].text
        let lo = sel.start.offset, hi = sel.end.offset
        guard let m = pattern.matches(in: text).first(where: {
            $0.range.lowerBound.utf16Offset(in: text) == lo && $0.range.upperBound.utf16Offset(in: text) == hi
        }) else { return false }
        let replacement = pattern.replacement(template, for: m, in: text)
        edit {
            let style = document.paragraphs[i].style(at: lo + 1)
            let at = lo + _deleteRange(in: i, lo ..< hi)  // tracked: the old text stays, deleted, before the new
            if !replacement.isEmpty {
                perform(.insertText(RichPosition(paragraph: i, offset: at), replacement,
                                    [Run(length: replacement.utf16.count, style: _typed(style))]))
            }
            _setCaret(RichPosition(paragraph: i, offset: at + replacement.utf16.count))
        }
        return true
    }

    /// Replace every match of `pattern` in the document; one undo step. Returns the count.
    @discardableResult
    public func replaceAll(_ pattern: TextPattern, with template: String) -> Int {
        var count = 0
        edit {
            for i in document.paragraphs.indices {
                let text = document.paragraphs[i].text
                let found = pattern.matches(in: text)
                // Backwards so earlier offsets stay valid.
                for m in found.reversed() {
                    let lo = m.range.lowerBound.utf16Offset(in: text)
                    let hi = m.range.upperBound.utf16Offset(in: text)
                    let replacement = pattern.replacement(template, for: m, in: text)
                    let style = document.paragraphs[i].style(at: lo + 1)
                    let at = lo + _deleteRange(in: i, lo ..< hi)  // tracked: the old text stays, deleted, before the new
                    if !replacement.isEmpty {
                        perform(.insertText(RichPosition(paragraph: i, offset: at), replacement,
                                            [Run(length: replacement.utf16.count, style: _typed(style))]))
                    }
                    count += 1
                }
            }
            _setCaret(document.clamped(selection.focus))
        }
        return count
    }

    /// How many matches `pattern` has in the document.
    public func countMatches(_ pattern: TextPattern) -> Int {
        document.paragraphs.reduce(0) { $0 + pattern.matches(in: $1.text).count }
    }

    /// Apply `transform` to every paragraph the selection touches.
    public func applyParagraphStyle(_ transform: (inout RichParagraphStyle) -> Void) {
        if let relay = formatRelay { relay { $0.applyParagraphStyle(transform) }; return }
        edit {
            for i in document.paragraphIndices(in: selection) {
                let old = document.paragraphs[i].style
                var new = old
                transform(&new)
                if new != old { perform(.setParagraphStyle(i, old: old, new: new)) }
            }
        }
    }

    /// Paragraph borders (W-PA-4): give each of `sides` (top, bottom, left, right, and insideH for the line between joined paragraphs; insideV is for cells and is ignored)
    /// the line, or take the line off when it is nil or "none". One undo step for every paragraph the selection touches.
    public func setParagraphBorders(_ sides: Set<CellSide>, _ line: CellBorderLine?) {
        let edge: BorderLine? = {
            guard let line, line.style != "none" else { return nil }
            var b = BorderLine(width: line.width, color: line.color, space: 1)
            if line.style != "single" { b.style = line.style }
            return b
        }()
        applyParagraphStyle { st in
            var b = st.borders ?? ParagraphBorders()
            if sides.contains(.top) { b.top = edge }
            if sides.contains(.bottom) { b.bottom = edge }
            if sides.contains(.left) { b.left = edge }
            if sides.contains(.right) { b.right = edge }
            if sides.contains(.insideH) { b.between = edge }
            st.borders = b.isEmpty ? nil : b
            if b.isEmpty { st.pBdrElement = false }
        }
    }

    /// Paragraph shading (W-PA-4): nil takes it off.
    public func setParagraphShading(_ color: Color?) {
        applyParagraphStyle { $0.fill = color }
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
            for (id, level) in targets.flatMap({ t in _listIdsSharing(t.0).map { ($0, t.1) } }) {
                let old = document.listFormats[id]?[level]
                let new = format.forLevel(level)
                if old != new { perform(.setListFormat(id, level: level, old: old, new: new)) }
            }
        }
    }

    /// Word's multilevel list gallery: the selected items become one list
    /// whose every level (0 to 8) takes its format from `scheme`.
    public func setMultilevelFormat(_ scheme: [ListLevelFormat]) {
        guard let top = scheme.first else { return }
        setListFormat(top)   // converts the kind, assigns the id, formats the levels in use
        edit {
            let ids = Set(document.paragraphIndices(in: selection).compactMap { document.paragraphs[$0].style.listId })
            for id in ids.sorted() {
                for (level, f) in scheme.prefix(9).enumerated() {
                    let old = document.listFormats[id]?[level]
                    if old != f { perform(.setListFormat(id, level: level, old: old, new: f)) }
                }
            }
        }
    }

    /// Word's Set Numbering Value (and Restart at 1): the caret's item and
    /// every later item of its list become a list of their own whose level
    /// starts at `n`. Deeper levels count from their own start again.
    public func setNumberingValue(_ n: Int) {
        let i = selection.focus.paragraph
        guard document.paragraphs[i].style.list == .numbered else { return }
        edit {
            if document.paragraphs[i].style.listId == nil { _assignListId(around: i) }
            let oldId = document.paragraphs[i].style.listId!
            let level = document.paragraphs[i].style.listLevel
            let fresh = _freshListId()
            for k in i ..< document.paragraphs.count where document.paragraphs[k].style.listId == oldId {
                let old = document.paragraphs[k].style
                var new = old
                new.listId = fresh
                perform(.setParagraphStyle(k, old: old, new: new))
            }
            for (lvl, f) in (document.listFormats[oldId] ?? [:]).sorted(by: { $0.key < $1.key }) {
                perform(.setListFormat(fresh, level: lvl, old: nil, new: f))
            }
            perform(.setListRestart(fresh, level: level, old: nil, new: max(0, n)))
            // Both halves stay one list definition: a later format change reaches both, and the
            // file writes one abstract list with a start override on the second.
            let key = document.listCounterOf[oldId] ?? oldId
            if document.listCounterOf[oldId] == nil { perform(.setListCounter(oldId, old: nil, new: key)) }
            perform(.setListCounter(fresh, old: nil, new: key))
        }
    }

    /// `id` and every other list id that shares its counter (a list split by Set Numbering Value).
    private func _listIdsSharing(_ id: String) -> [String] {
        guard let key = document.listCounterOf[id] else { return [id] }
        let others = document.listCounterOf.filter { $0.value == key && $0.key != id }.keys.sorted()
        return [id] + others
    }

    public func restartNumbering() { setNumberingValue(1) }

    /// The list item above the caret's that Continue Numbering would join: the
    /// nearest earlier numbered item of another list.
    private func _previousListId() -> String? {
        let i = selection.focus.paragraph
        let mine = document.paragraphs[i].style.listId
        var k = i - 1
        while k >= 0 {
            let s = document.paragraphs[k].style
            if s.list == .numbered, let id = s.listId, id != mine { return id }
            if s.list == .numbered, s.listId == mine { return nil }
            k -= 1
        }
        return nil
    }

    /// True when the caret paragraph is a numbered (not bullet) list item.
    public var isNumberedItem: Bool {
        document.paragraphs[selection.focus.paragraph].style.list == .numbered
    }

    /// The number the caret item shows now (1 when it is not a plain number), the prompt's start value.
    public var currentNumberValue: Int {
        let labels = RichListNumbering.labels(document)
        guard let l = labels[selection.focus.paragraph] else { return 1 }
        let digits = l.filter { $0.isNumber }
        return Int(digits) ?? 1
    }

    public var canContinueNumbering: Bool {
        document.paragraphs[selection.focus.paragraph].style.list == .numbered && _previousListId() != nil
    }

    /// Word's Continue Numbering: the caret's item and the rest of its list join the list above.
    public func continueNumbering() {
        let i = selection.focus.paragraph
        guard document.paragraphs[i].style.list == .numbered, let target = _previousListId() else { return }
        edit {
            if document.paragraphs[i].style.listId == nil { _assignListId(around: i) }
            let mine = document.paragraphs[i].style.listId!
            for k in i ..< document.paragraphs.count where document.paragraphs[k].style.listId == mine {
                let old = document.paragraphs[k].style
                var new = old
                new.listId = target
                perform(.setParagraphStyle(k, old: old, new: new))
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

    /// Word's Ctrl+M / Ctrl+Shift+M (`hanging` false) and Ctrl+T / Ctrl+Shift+T (`hanging` true): the left indent moves to
    /// the next (or, `forward` false, the previous) default tab stop. Ctrl+M carries the first line along; Ctrl+T leaves
    /// the first line where it stands, so the rest of the paragraph hangs under it (and Ctrl+Shift+T stops where the
    /// hang runs out). One undo step.
    public func stepIndent(forward: Bool, hanging: Bool) {
        let step = (document.defaultTabStop ?? 36) > 0.01 ? (document.defaultTabStop ?? 36) : 36
        applyParagraphStyle { s in
            let left = s.indentLeft
            let next = forward ? (floor(left / step + 1e-6) + 1) * step : max(0, (ceil(left / step - 1e-6) - 1) * step)
            if hanging {
                let first = left + s.firstLineIndent
                let to = forward ? next : min(left, max(next, first))
                s.indentLeft = to
                s.firstLineIndent = first - to
            } else {
                s.indentLeft = next
            }
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
        guard !_selectionLocked() else { return nil }
        guard let text = copySelection() else { return nil }
        deleteSelection()
        return text
    }

    /// Paste: if the system text is exactly what we last copied, paste the
    /// rich fragment; otherwise plain text.
    public func paste(text: String) {
        guard !_selectionLocked() else { return }
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
        guard !_selectionLocked() else { return nil }
        guard let data = copySelectionData() else { return nil }
        guard hasSelection else { return data }
        edit {
            _deleteSelectionOps()
            _tidySpacesAtCaret()
        }
        return data
    }

    /// Word's Paste Options (W-ED-1).
    public enum PasteMode: Equatable, Sendable {
        /// What the clipboard holds, formatting and all (the plain Paste).
        case keepSource
        /// The destination's fonts, sizes, colours and paragraph look; the
        /// source keeps its bold, italic, underline, strike-through,
        /// super/subscript and links.
        case mergeFormatting
        /// The clipboard's text alone, in the style at the caret.
        case textOnly
        /// The clipboard's picture alone.
        case picture
    }

    /// Whether `data` can be pasted in `mode` (the Paste Options entries
    /// that cannot are greyed).
    public func canPaste(_ data: ClipboardData, mode: PasteMode) -> Bool {
        switch mode {
        case .keepSource, .mergeFormatting: return data.text?.isEmpty == false || data.png != nil || copiedFragment != nil
        case .textOnly: return data.text?.isEmpty == false
        case .picture: return data.png.flatMap { ImageAttachment.pngPixelSize($0) } != nil
        }
    }

    /// Paste in one undoable step by Paste Options choice. The Paste Options button then offers the other ways.
    public func paste(data: ClipboardData, mode: PasteMode) {
        let before = revision
        _paste(data: data, mode: mode)
        notePaste(data, mode: mode, revisionBefore: before)
    }

    private func _paste(data: ClipboardData, mode: PasteMode) {
        guard !_selectionLocked() else { return }
        switch mode {
        case .keepSource:
            paste(data: data)
        case .textOnly:
            guard let text = data.text, !text.isEmpty else { return }
            edit {
                if hasSelection { _deleteSelectionOps() }
                insertText(text.replacingAll("\r\n", with: "\n"))
            }
        case .picture:
            guard let png = data.png, let px = ImageAttachment.pngPixelSize(png) else { return }
            _ = px
            paste(data: ClipboardData(text: nil, png: png))
        case .mergeFormatting:
            var fragment: [RichParagraph]?
            if let text = data.text, let own = copiedFragment, own.map(\.text).joined(separator: "\n") == text {
                fragment = own
            } else if let codec = clipboardCodec, let decoded = codec.decode(data), !decoded.isEmpty {
                fragment = decoded
            }
            guard var fragment else { paste(data: data); return }
            let dest = document.paragraphs.indices.contains(caret.paragraph) ? document.paragraphs[caret.paragraph].style : RichParagraphStyle()
            for i in fragment.indices where fragment[i].image == nil {
                fragment[i].style = dest
                fragment[i].runs = fragment[i].runs.map { run in
                    var kept = CharStyle.plain
                    kept.bold = run.style.bold; kept.italic = run.style.italic
                    kept.underline = run.style.underline; kept.strikethrough = run.style.strikethrough
                    kept.script = run.style.script; kept.link = run.style.link; kept.linkTip = run.style.linkTip
                    return Run(length: run.length, style: kept)
                }
            }
            insertFragment(fragment, smart: true)
        }
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
                if !text.containsSubstring("\n") {
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

/// A side of a cell block that a border command names.
public enum CellSide: String, CaseIterable, Hashable, Sendable {
    case top, bottom, left, right, insideH, insideV
}

/// One border line: Word's line style ("single", "double", "dashed",
/// "dotted", or "none" for no line), width in points (one of Word's nine, 1/4 to 6; a heavy
/// line is "single" with a large width, as Word writes it) and colour (nil
/// is automatic).
public struct CellBorderLine: Hashable, Sendable {
    public static let styles = ["single", "double", "dashed", "dotted", "none"]
    public var style: String
    public var width: Double
    public var color: Color?
    /// The colour's theme link (` w:themeColor="accent2" w:themeShade="BF"`, from `WordTheme.attrs`), written after the
    /// colour so the line keeps following the theme.
    public var themeAttrs: String?
    public init(style: String = "single", width: Double = 0.5, color: Color? = nil, themeAttrs: String? = nil) {
        self.themeAttrs = color == nil ? nil : themeAttrs
        self.style = Self.styles.contains(style) ? style : "single"
        // Word has only these widths and rounds any other to the nearest one.
        self.width = Self.widths.min { abs($0 - width) < abs($1 - width) } ?? 0.5
        self.color = color
    }
    public static let widths: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2.25, 3, 4.5, 6]
    public static let none = CellBorderLine(style: "none")

    func xml(_ side: String) -> String {
        if style == "none" { return "<w:\(side) w:val=\"nil\"/>" }
        let hex = color.map { v -> String in
            let h = String(v.value & 0xFFFFFF, radix: 16, uppercase: true)
            return String(repeating: "0", count: 6 - h.count) + h
        } ?? "auto"
        return "<w:\(side) w:val=\"\(style)\" w:sz=\"\(Int((width * 8).rounded()))\" w:space=\"0\" w:color=\"\(hex)\"\(themeAttrs ?? "")/>"
    }
}

/// Word's theme-colour attributes for a colour picked from the theme grid.
public enum WordTheme {
    static let slots = ["background1", "text1", "background2", "text2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6"]

    /// The attributes for slot 0...9 (Background 1, Text 1, Background 2, Text 2, Accent 1...6) at OOXML's `lumMod` and
    /// `lumOff` in percent. Lighter steps are a tint of the slot, darker ones a shade (Word writes both as hex bytes of
    /// the share kept: Lighter 40 percent is tint 99, Darker 25 percent is shade BF). `fill`: a shading
    /// (`w:themeFill`), otherwise a line or text colour (`w:themeColor`).
    public static func attrs(slot: Int, lumMod: Int, lumOff: Int, fill: Bool) -> String? {
        guard slot >= 0, slot < slots.count else { return nil }
        let base = fill ? "w:themeFill" : "w:themeColor"
        var out = " \(base)=\"\(slots[slot])\""
        if lumMod < 100 {
            let hex = String(Int((Double(lumMod) * 2.55).rounded()), radix: 16, uppercase: true)
            let kind = lumOff > 0 ? "Tint" : "Shade"
            out += " \(base == "w:themeFill" ? "w:themeFill" : "w:theme")\(kind)=\"\(hex.count < 2 ? "0" + hex : hex)\""
        }
        return out
    }
}
