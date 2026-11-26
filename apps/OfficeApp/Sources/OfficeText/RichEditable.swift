// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichEditable: the editing widget. A Listener over a CustomPaint whose
// painter repaints on a Listenable, so a keystroke goes controller →
// layout (one paragraph) → repaint, with no widget rebuild in between.
// Scrolling is the widget's own (`scrollY` + wheel), as the Text Editor and
// TerminalView do it: a Scrollable would repaint through a layer offset and
// never re-invoke the painter, so visible-range culling could not follow it.
//
// Keyboard input comes as raw KeyData through a FocusNode and is normalised
// by KeyChordTracker, so the same chords work on the DRM shell (keysyms)
// and every windowed host (Flutter ids). Timers use DispatchQueue with a
// generation token — Foundation.Timer never fires on the DRM embedder.

import Flutter
import FlutterSwiftBridge
import Foundation

public final class RichEditable: StatefulWidget {
    public let controller: RichDocumentController
    public let theme: RichTextTheme
    /// Space around the content column, in logical pixels.
    public let padding: EdgeInsets
    public let focusNode: FocusNode?
    public let autofocus: Bool
    public let backgroundColor: Color?
    /// The shape being typed into: its own frame is drawn by the editor over it, so the page leaves its frame out.
    public let hiddenFrameID: String?
    /// Zoom, 1.0 = 100%.
    public let zoom: Double
    /// Paginate onto paper of this size; nil is a continuous column.
    public let pageSetup: PageSetup?
    /// Paper colour in paged mode.
    public let pageColor: Color
    /// Called after each paint with the caret rectangle in the widget's
    /// coordinates (nil when unfocused) — the IME candidate-panel anchor.
    public let onCaretRect: ((Rect?) -> Void)?
    /// Called after a paint whenever (caret page, page count) changed —
    /// 1-based, for a status bar.
    public let onPageInfo: ((Int, Int) -> Void)?
    /// Consulted before the editor's own chords for every key-down with
    /// the platform's accelerator held; return true to claim it (an app's
    /// ⌘S, ⌘O, ⌘F). Also sees Escape.
    public let onShortcut: ((KeyData, KeyModifiers) -> Bool)?
    /// Slides' border pen and eraser: when set, a mouse press (and a drag) near a table cell's edge calls it with the cell
    /// (table, row, column) and the side, instead of placing the caret.
    public let onCellEdge: ((String, Int, Int, CellSide) -> Void)?
    /// True when a pen stroke starts, false when it ends (so the host can make the whole stroke one undo step).
    public let onCellEdgeStroke: ((Bool) -> Void)?
    /// Writer's Draw Table: when set, a drag calls it with the cell it began in (nil outside a table) and the drag's
    /// size in flow pixels, instead of selecting.
    public let onDrawTable: ((DrawCell?, Double, Double) -> Void)?
    /// The link under the pointer, or nil as it leaves one — for a status bar.
    public let onLinkHover: ((String?) -> Void)?
    /// ⌘-click on a link. Nil opens it through the host.
    public let onLinkActivate: ((String) -> Void)?
    /// A click in a note on the page, or a double-click on a note's mark: the note and its box in window coordinates.
    public let onNoteActivate: ((NoteReference, Rect) -> Void)?
    /// A pointer selection gesture ended (click, drag, double or triple click)
    /// — when Word's Format Painter applies (a bare click may leave no selection).
    public let onSelectionGestureEnd: (() -> Void)?
    /// A double-click in a page's header or footer band (edit that part in the strip).
    public let onHeaderFooterEdit: ((KeptHeaderFooter.Kind) -> Void)?
    /// Checks paragraphs as they are shown and underlines misspellings.
    public let spellChecker: RichSpellChecker?
    /// A right click, with the pointer's position in global coordinates.
    /// The caret has moved there unless the click was inside the selection.
    public let onContextMenu: ((Offset) -> Void)?
    /// A finger's selection or caret wants the system edit menu: the rect to
    /// point at in global coordinates, or nil to take the menu away.
    public let onTouchMenu: ((Rect?) -> Void)?
    /// False pins the text at the top and draws no scroll thumb: a slide's
    /// text box, whose text overflows its frame rather than scrolling.
    public let scrolls: Bool
    /// A click (no drag) on a selected plain text box: its paragraph index, inline id and drawn rect in this widget's coordinates.
    public let onTextBoxEnter: ((Int, String?, Rect) -> Void)?
    /// Reported after a paint whenever the selected picture's drawn rect moved (scroll, zoom, layout): lets an editor laid
    /// over a text box follow it. Nil when no picture is selected.
    public let onBoxRect: ((Rect?) -> Void)?
    /// Reported after a paint whenever the height of the laid-out text (logical pixels, no padding) changed: lets the box
    /// holding this editor grow with what is typed.
    public let onContentHeight: ((Double) -> Void)?

    public init(key: (any Key)? = nil, controller: RichDocumentController,
                theme: RichTextTheme = RichTextTheme(),
                padding: EdgeInsets = EdgeInsets(left: 24, top: 24, right: 24, bottom: 24),
                focusNode: FocusNode? = nil, autofocus: Bool = true,
                backgroundColor: Color? = nil, hiddenFrameID: String? = nil, zoom: Double = 1.0,
                pageSetup: PageSetup? = nil, pageColor: Color = Color(0xFFFFFFFF),
                onCaretRect: ((Rect?) -> Void)? = nil,
                onPageInfo: ((Int, Int) -> Void)? = nil,
                onShortcut: ((KeyData, KeyModifiers) -> Bool)? = nil,
                onCellEdge: ((String, Int, Int, CellSide) -> Void)? = nil,
                onCellEdgeStroke: ((Bool) -> Void)? = nil,
                onDrawTable: ((DrawCell?, Double, Double) -> Void)? = nil,
                onLinkHover: ((String?) -> Void)? = nil,
                onLinkActivate: ((String) -> Void)? = nil,
                onNoteActivate: ((NoteReference, Rect) -> Void)? = nil,
                onSelectionGestureEnd: (() -> Void)? = nil,
                onHeaderFooterEdit: ((KeptHeaderFooter.Kind) -> Void)? = nil,
                onContextMenu: ((Offset) -> Void)? = nil,
                onTouchMenu: ((Rect?) -> Void)? = nil,
                spellChecker: RichSpellChecker? = nil,
                scrolls: Bool = true,
                onTextBoxEnter: ((Int, String?, Rect) -> Void)? = nil,
                onBoxRect: ((Rect?) -> Void)? = nil,
                onContentHeight: ((Double) -> Void)? = nil) {
        self.onContentHeight = onContentHeight
        self.onTextBoxEnter = onTextBoxEnter
        self.onBoxRect = onBoxRect
        self.controller = controller
        self.theme = theme
        self.padding = padding
        self.focusNode = focusNode
        self.autofocus = autofocus
        self.backgroundColor = backgroundColor
        self.hiddenFrameID = hiddenFrameID
        self.zoom = zoom
        self.pageSetup = pageSetup
        self.pageColor = pageColor
        self.onCaretRect = onCaretRect
        self.onPageInfo = onPageInfo
        self.onShortcut = onShortcut
        self.onCellEdge = onCellEdge
        self.onCellEdgeStroke = onCellEdgeStroke
        self.onDrawTable = onDrawTable
        self.onLinkHover = onLinkHover
        self.onLinkActivate = onLinkActivate
        self.onNoteActivate = onNoteActivate
        self.onSelectionGestureEnd = onSelectionGestureEnd
        self.onHeaderFooterEdit = onHeaderFooterEdit
        self.onContextMenu = onContextMenu
        self.onTouchMenu = onTouchMenu
        self.spellChecker = spellChecker
        self.scrolls = scrolls
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return RichEditableState()
    }
}

public final class RichEditableState: State<StatefulWidget> {
    private let _leakProbe = LeakProbe("RichEditableState")
    private var _ownedFocus: FocusNode?
    private var _focus: FocusNode!
    private let _chords = KeyChordTracker()
    private var _layout: RichLayout!
    private let _repaint = ChangeNotifier()
    private var _painter: _RichEditablePainter!
    private var _controller: RichDocumentController!

    // Viewport state.
    private var _scrollY = 0.0
    private var _viewport = Size.zero
    /// Where the canvas's left edge sits in the widget (pages are centred).
    private var _originX = 0.0
    private var _lastPageInfo = (0, 0)
    private var _stickyX: Double?

    // Caret blink.
    private var _caretVisible = true
    private var _blinkGeneration = 0

    // Mouse.
    private var _dragging = false
    /// A finger on the document: it scrolls, and a tap places the caret
    /// on lift. (A mouse drag selects; a finger drag that selected could
    /// never scroll a page on a phone.)
    private var _touchScroll: (startY: Double, scrollStart: Double, lastY: Double, lastTime: Double, velocity: Double, moved: Bool)? = nil
    /// Shift-arrow style selection in progress (ends when Shift is released).
    private var _kbSelecting = false
    /// A picture-handle drag: which handle (0–7, clockwise from top-left),
    /// where it started, the picture's size then, and the live size.
    private var _handleDrag: (index: Int, handle: Int, start: Offset, size: Size, inline: String?)? = nil
    private var _dragSize: Size? = nil
    /// A floating picture dragged by its body: which one, where the press was, and the live offset.
    private var _lastBoxRect: Rect?
    private var _lastContentHeight = -1.0
    private var _moveDrag: (index: Int, inline: String?, start: Offset)? = nil
    private var _moveDelta: Offset? = nil
    /// A shape waiting from Insert > Shapes, pressed on the page: where the press was and where the mouse is now.
    private var _shapeDraw: (start: Offset, now: Offset)? = nil
    // Touch selection: a long press selects the word under the finger, a double
    // tap does too, and a selection shows a handle at each end to drag.
    private var _touchMode = false
    private var _selHandle: (fixed: RichPosition?, grabDY: Double, moved: Bool)? = nil
    /// A knob under the caret to drag it, after a finger placed it.
    private var _caretHandleShown = false
    /// Where the finger is while a handle is dragged: the magnifier follows it.
    private var _loupeAt: Offset? = nil
    static let loupeRadius = 52.0
    static let loupeZoom = 1.6
    private var _longPressGen = 0
    private var _longPressed = false
    /// Fingers down, by pointer id (view coordinates too, for where the menu goes). Two fingers that land and lift
    /// together without moving are a tap with two fingers: the right-click menu, as a long press opens it.
    private var _fingers: [Int: (local: Offset, global: Offset)] = [:]
    private var _twoFinger: (at: Double, local: Offset, global: Offset)? = nil
    private var _twoFingerActive = false
    private var _lastTap: (at: Double, pos: Offset) = (0, Offset(-100, -100))
    static let knobRadius = 7.0

    /// The handle under a hovering pointer, for its cursor.
    private var _hoverHandle: Int? = nil
    private var _hoverOverImage = false
    private var _hoverLink: String? = nil
    /// The platform text-input connection (IME), when enabled.
    private var _textInput: RichTextInputConnection? = nil
    /// A column-border drag: the table, the column whose right edge moves,
    /// the pointer's start x (points), and the widths at the start.
    private var _columnDrag: (table: String, column: Int, startX: Double, widths: [Double])? = nil
    private var _columnDragWidths: [Double]? = nil
    private var _hoverColumnBorder = false
    /// A row's bottom border being dragged: the table and row, the pointer's start y and the row's height (points), and
    /// the table's edges relative to the pointer's x; `_rowDragHeight` is the height it would take now.
    private var _rowDrag: (table: String, row: Int, startY: Double, height: Double, canvasY: Double, left: Double, right: Double, canvasX: Double)? = nil
    private var _rowDragHeight: Double? = nil
    private var _hoverRowBorder = false
    /// A press inside the selection: a drag of the selected text once the
    /// pointer moves, a click that collapses the selection if it does not.
    private var _textDrag: (start: Offset, active: Bool)? = nil
    private var _edgeStroke: String? = nil
    private var _edgeDragging = false
    private var _drawFrom: (local: Offset, cell: DrawCell?)? = nil
    private var _edgeLast: Offset? = nil
    /// The pen along a move: sampled every few pixels so a fast drag cannot step over an edge.
    private func _edgeToolAlong(_ to: Offset) {
        if let from = _edgeLast {
            let dx = to.dx - from.dx, dy = to.dy - from.dy
            let n = max(1, Int((dx * dx + dy * dy).squareRoot() / 4))
            for i in 1 ... n { _ = _edgeTool(Offset(from.dx + dx * Double(i) / Double(n), from.dy + dy * Double(i) / Double(n))) }
        } else { _ = _edgeTool(to) }
        _edgeLast = to
    }
    /// The pen or eraser at a point; true when an edge was near enough to take it.
    private func _edgeTool(_ local: Offset) -> Bool {
        guard let tool = _w.onCellEdge, _layout.width > 0, _layout.count > 0 else { return false }
        _syncLayoutIfNeeded()
                guard let e = _layout.cellEdge(at: _layout.flowPoint(_canvasPoint(local)), tolerance: 8, _controller.document) else { return false }
        let key = "\(e.table).\(e.row).\(e.column).\(e.side)"
        if key != _edgeStroke { _edgeStroke = key; tool(e.table, e.row, e.column, e.side) }
        return true
    }
    /// Where the dragged text would land, painted as a second caret.
    private var _dropPosition: RichPosition? = nil
    /// A spell-check pass is scheduled (one at a time, after an idle).
    private var _spellScheduled = false
    /// Trackpad scrolling: the last pan's velocity (px per frame) and the
    /// generation of the momentum run, so a new touch cancels the old one.
    private var _panVelocity = 0.0
    private var _panLastTime: Duration? = nil
    private var _momentumGeneration = 0
    /// A drag begun by a double or triple click: the unit first selected,
    /// and whether the units are paragraphs (else words).
    private var _unitDrag: (origin: RichSelection, paragraphs: Bool)? = nil
    static let handleSize = 8.0
    private var _clickStreak = 0
    private var _lastClickAt = 0.0
    private var _lastClickPos = Offset.zero

    private var _w: RichEditable { widget as! RichEditable }

    /// `STARLING_RICHTEXT_PERF=1` prints per-change layout and paint times
    /// to stderr (raw write: print() is block-buffered through pipes).
    private static let _perf = ProcessInfo.processInfo.environment["STARLING_RICHTEXT_PERF"] != nil
    private var _lastLayoutMicros = 0

    private static func _log(_ line: String) {
        let s = line + "\n"
        FileHandle.standardError.write(Data(s.utf8))
    }

    /// Current scroll offset in logical pixels; settable for a ruler or a
    /// scrollbar that lives outside the widget.
    public var scrollY: Double {
        get { _scrollY }
        set {
            _scrollY = newValue
            _clampScroll()
            _repaint.notifyListeners()
        }
    }

    public var contentHeight: Double {
        (_layout?.canvasSize.height ?? 0) + _w.padding.top + _w.padding.bottom
    }

    /// Pages in the current layout (1 when continuous).
    public var pageCount: Int { _layout?.pageCount ?? 1 }

    /// The page the caret is on, 1-based.
    public var caretPage: Int {
        guard let layout = _layout, layout.isPaged, layout.width > 0 else { return 1 }
        let r = layout.canvasCaretRect(_controller.caret, _controller.document)
        return layout.page(atCanvasY: r.top) + 1
    }

    /// The page (from 1) at the top of the view — a third of the way
    /// down it, so a page's tail at the top does not name the page.
    public var visiblePage: Int {
        guard let layout = _layout, layout.isPaged, layout.width > 0 else { return 1 }
        return layout.page(atCanvasY: _scrollY - _w.padding.top + _viewport.height / 3) + 1
    }

    public var viewportSize: Size { _viewport }

    /// The paragraph at the top of the view (0 before layout, or at the
    /// document's start): where a reader is, for a history entry that
    /// brings them back here.
    public var topParagraph: Int {
        guard let layout = _layout, layout.width > 0 else { return 0 }
        let canvasY = _scrollY - _w.padding.top + 1
        guard canvasY > 0 else { return 0 }
        // The first column of the page under the view's top edge, when paged.
        let y = layout.isPaged ? layout.flowPoint(Offset(0, canvasY)).dy : canvasY
        return layout.paragraphIndex(atY: y)
    }

    public var focusNode: FocusNode { _focus }

    // MARK: Lifecycle

    public override func initState() {
        super.initState()
        _controller = _w.controller
        if let node = _w.focusNode {
            _focus = node
        } else {
            _ownedFocus = FocusNode(debugLabel: "RichEditable")
            _focus = _ownedFocus
        }
        bind(_focus)
        _focus.onKeyData = { [weak self] keyData in
            return self?._handleKey(keyData) ?? false
        }
        _focus.onFocusChange = { [weak self] focused in
            guard let self else { return }
            if !focused { self._chords.reset() }
            if focused { self._textInput?.attach() } else { self._textInput?.detach() }
            // A phone has to be asked for its keyboard (see TextBox) — unless the
            // platform's text-input view has the editor, which raises its own.
            if focused, !self._controller.readOnly, self._textInput?.isAttached != true { SoftKeyboard.show() }
            self._caretVisible = true
            self._restartBlink()
            self._repaint.notifyListeners()
        }
        _layout = RichLayout(theme: _w.theme, paragraphCount: _controller.document.paragraphs.count)
        _controller.rowHeightProbe = { [weak self] i in self?._layout?.rowRect(i)?.height }
        _layout.scale = _w.zoom
        _layout.pageSetup = _w.pageSetup
        _layout.onNeedsRepaint = { [weak self] in self?._repaint.notifyListeners() }
        _layout.spellChecker = _w.spellChecker
        _painter = _RichEditablePainter(state: self, repaint: _repaint)
        // Under an owner, not bare: a bare removeListener takes the most
        // recently added one, and when this editor is remounted (its
        // ancestor moved into a Stack — Office's Backstage opening and
        // closing) the new state subscribes BEFORE the old one is disposed.
        // The old state's dispose then took the new state's listener, and
        // the page stopped following the document: typing changed the text
        // and the word count, and nothing was redrawn.
        _controller.addListener({ [weak self] in self?._onControllerChanged() }, owner: self)
        SystemFontsNotifier.shared.addListener({ [weak self] in
            guard let self else { return }
            self._layout.invalidateForFonts()
            self._syncLayout()
            self._ensureCaretVisible()
            self._repaint.notifyListeners()
        }, owner: self)
        if RichTextInputConnection.enabled { _textInput = RichTextInputConnection(controller: _controller) }
        if _w.autofocus { _focus.requestFocus() }
        _restartBlink()
    }

    public override func didUpdateWidget(_ oldWidget: StatefulWidget) {
        super.didUpdateWidget(oldWidget)
        let old = oldWidget as! RichEditable
        if old.controller !== _w.controller {
            old.controller.removeListeners(owner: self)
            _controller = _w.controller
            _controller.addListener({ [weak self] in self?._onControllerChanged() }, owner: self)
            _layout = RichLayout(theme: _w.theme, paragraphCount: _controller.document.paragraphs.count)
            _layout.onNeedsRepaint = { [weak self] in self?._repaint.notifyListeners() }
        } else if old.theme !== _w.theme {
            _layout = RichLayout(theme: _w.theme, paragraphCount: _controller.document.paragraphs.count)
            _layout.onNeedsRepaint = { [weak self] in self?._repaint.notifyListeners() }
        }
        if _layout.scale != _w.zoom { _layout.scale = _w.zoom }
        if _layout.spellChecker !== _w.spellChecker { _layout.spellChecker = _w.spellChecker }
        if _layout.pageSetup != _w.pageSetup { _layout.pageSetup = _w.pageSetup }
        _repaint.notifyListeners()
    }

    public override func dispose() {
        _blinkGeneration += 1
        SystemFontsNotifier.shared.removeListeners(owner: self)
        _controller.removeListeners(owner: self)
        _textInput?.detach()
        _ownedFocus?.dispose()
        super.dispose()
    }

    // MARK: Controller → layout

    private func _onControllerChanged() {
        let t0 = Self._perf ? DispatchTime.now().uptimeNanoseconds : 0
        _syncLayout()
        if Self._perf { _lastLayoutMicros = Int((DispatchTime.now().uptimeNanoseconds - t0) / 1000) }
        _ensureCaretVisible()
        _caretVisible = true
        _restartBlink()
        _repaint.notifyListeners()
        _textInput?.sync()
    }

    private func _syncLayout() {
        let changes = _controller.drainChanges()
        if !changes.isEmpty {
            _layout.apply(changes, paragraphCount: _controller.document.paragraphs.count)
        }
        if _layout.width > 0 { _layout.ensureLaidOut(_controller.document) }
    }

    private func _clampScroll() {
        let maxY = _w.scrolls ? max(0, contentHeight - _viewport.height) : 0
        _scrollY = max(0, min(_scrollY, maxY))
    }

    private func _ensureCaretVisible() {
        guard _viewport.height > 0, _layout.width > 0 else { return }
        let c = _layout.canvasCaretRect(_controller.caret, _controller.document)
        let top = c.top + _w.padding.top
        let bottom = c.bottom + _w.padding.top
        let margin = 8.0
        let placement = _controller.pendingReveal
        _controller.pendingReveal = .visible
        if placement == .top {
            _scrollY = max(0, top - margin)
            _clampScroll()
            return
        }
        if top < _scrollY + margin {
            // (To the document's start is to the top of its first page,
            // margin and all, as ⌘↑ leaves a view in Word — not to the
            // first line with the paper above it cut off.)
            let atStart = _controller.caret.paragraph == 0 && _controller.caret.offset == 0
            _scrollY = atStart ? 0 : max(0, top - margin)
        } else if bottom > _scrollY + _viewport.height - margin {
            _scrollY = bottom - _viewport.height + margin
        }
        _clampScroll()
    }

    /// Scroll so the caret is visible; public for toolbars that move it.
    public func revealCaret() {
        _ensureCaretVisible()
        _repaint.notifyListeners()
    }

    // MARK: Blink

    private func _restartBlink() {
        _blinkGeneration += 1
        let gen = _blinkGeneration
        _scheduleBlink(gen)
    }

    private func _scheduleBlink(_ gen: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(530)) { [weak self] in
            guard let self, self._blinkGeneration == gen else { return }
            guard self._focus.hasFocus else { return }
            self._caretVisible.toggle()
            self._repaint.notifyListeners()
            self._scheduleBlink(gen)
        }
    }

    // MARK: Keyboard

    private func _handleKey(_ keyData: KeyData) -> Bool {
        _caretHandleShown = false
        let shiftWas = _chords.shift
        if _chords.track(keyData) {
            // Shift let go after a keyboard selection: that selection has
            // ended, which is when the Format Painter applies.
            if shiftWas, !_chords.shift, _kbSelecting {
                _kbSelecting = false
                if _controller.hasSelection { _w.onSelectionGestureEnd?() }
            }
            // A modifier alone: the pointer over a link changes shape with ⌘.
            if _hoverLink != nil || _textDrag?.active == true { setState {} }
            return false
        }
        guard keyData.type == .down || keyData.type == .repeat else { return false }
        let c = _controller!
        // While an input method composes, every key is its: Enter commits
        // the candidate, Escape cancels, arrows move inside the marked text,
        // Backspace shortens it. Taking Enter here split the paragraph with
        // "zhong wen" still underlined (seen 2026-10-13 with Pinyin).
        if _textInput?.isAttached == true, c.composingRange != nil { return false }
        let shift = _chords.shift
        let key = KeyChordTracker.named(keyData.logical)
        if shift, key != nil, key != .escape { _kbSelecting = true }
        if let onShortcut = _w.onShortcut, _chords.primary || key == .escape,
           onShortcut(keyData, _chords.modifiers) {
            return true
        }
        var keepStickyX = false

        switch key {
        case .left:
            if _chords.word { c.moveWordLeft(extend: shift) }
            else if _chords.primary && KeyModifiers.primary == .meta { _moveLineEdge(home: true, extend: shift) }
            else { c.moveLeft(extend: shift) }
        case .right:
            if _chords.word { c.moveWordRight(extend: shift) }
            else if _chords.primary && KeyModifiers.primary == .meta { _moveLineEdge(home: false, extend: shift) }
            else { c.moveRight(extend: shift) }
        case .up:
            keepStickyX = true
            // (To the document's start or end shows it, whether or not
            // the caret was there already and the view elsewhere.)
            if _chords.primary && KeyModifiers.primary == .meta { c.moveToDocumentStart(extend: shift); revealCaret() }
            else if _chords.alt { c.moveToParagraphStart(extend: shift) }
            else { _moveVertical(down: false, extend: shift) }
        case .down:
            keepStickyX = true
            if _chords.primary && KeyModifiers.primary == .meta { c.moveToDocumentEnd(extend: shift); revealCaret() }
            else if _chords.alt { c.moveToParagraphEnd(extend: shift) }
            else { _moveVertical(down: true, extend: shift) }
        case .home:
            if _chords.control { c.moveToDocumentStart(extend: shift) }
            else { _moveLineEdge(home: true, extend: shift) }
        case .end:
            if _chords.control { c.moveToDocumentEnd(extend: shift) }
            else { _moveLineEdge(home: false, extend: shift) }
        case .pageUp:
            keepStickyX = true
            _movePage(down: false, extend: shift)
        case .pageDown:
            keepStickyX = true
            _movePage(down: true, extend: shift)
        case .backspace where c.groupChild != nil && c.editGroupChild(.delete): break   // a picked child of a group goes
        case .delete where c.groupChild != nil && c.editGroupChild(.delete): break
        case .backspace:
            if _chords.word { c.deleteWordBackward() }
            else if _chords.primary && KeyModifiers.primary == .meta { _deleteToLineStart() }
            else { c.deleteBackward() }
        case .delete:
            if _chords.word { c.deleteWordForward() } else { c.deleteForward() }
        case .enter:
            // ⇧⏎ is a line break inside the paragraph.
            if shift { c.insertLineBreak() } else { c.insertParagraphBreak() }
        case .tab:
            if c.isInCell { c.moveToAdjacentCell(forward: !shift) }
            // (At the start of a list item Tab is the item's level, as in
            // Word and as the welcome page says — it typed a tab
            // character after the bullet instead: seen 2026-10-13.)
            else if shift { c.indent(-1) }
            else if c.hasSelection || (c.currentParagraphStyle.list != nil && c.caret.offset == 0) { c.indent(1) }
            else { c.insertText("\t") }
        case .escape:
            if c.hasSelection { c.moveTo(c.caret, extend: false) } else { return false }
        default:
            if _chords.primary, !_chords.alt, let letter = KeyChordTracker.letter(keyData.logical) {
                switch letter {
                case "a": c.selectAll()
                case "c": _copy()
                case "x": _cut()
                case "v": if shift { return false } else { _paste() }   // (⇧⌘V is the Format Painter's paste, handled by the shell; plain paste is ⌥⌘V: W-P0-5)
                case "z": if shift { c.redo() } else { c.undo() }
                case "y": c.redo()
                case "b": c.toggleBold()
                case "i": c.toggleItalic()
                case "u": c.toggleUnderline()
                default: return false
                }
            } else if let text = _chords.typedText(keyData) {
                // With the text-input plugin connected the characters
                // arrive from it (composed, accented, or plain); declining
                // the key here is what lets the plugin have it.
                if _textInput?.isAttached == true { return false }
                c.insertTyped(text)
            } else {
                return false
            }
        }
        if !keepStickyX { _stickyX = nil }
        return true
    }

    private func _moveLineEdge(home: Bool, extend: Bool) {
        _syncLayoutIfNeeded()
        let pos = _controller.caret
        let (start, end) = _layout.lineBounds(pos, _controller.document)
        _controller.moveTo(RichPosition(paragraph: pos.paragraph, offset: home ? start : end), extend: extend)
    }

    /// ⌘⌫ on the Mac: the line's text before the caret goes.
    private func _deleteToLineStart() {
        _syncLayoutIfNeeded()
        let pos = _controller.caret
        let (start, _) = _layout.lineBounds(pos, _controller.document)
        _controller.deleteBackward(toOffset: start)
    }

    private func _moveVertical(down: Bool, extend: Bool) {
        _syncLayoutIfNeeded()
        let pos = _controller.caret
        let rect = _layout.caretRect(pos, _controller.document)
        let x = _stickyX ?? rect.left
        _stickyX = x
        if let next = _layout.verticalNeighbour(of: pos, x: x, down: down, _controller.document) {
            _controller.moveTo(next, extend: extend)
        } else {
            _controller.moveTo(down ? _controller.document.endPosition : .start, extend: extend)
        }
    }

    private func _movePage(down: Bool, extend: Bool) {
        _syncLayoutIfNeeded()
        let pos = _controller.caret
        let rect = _layout.caretRect(pos, _controller.document)
        let x = _stickyX ?? rect.left
        _stickyX = x
        let step = max(40, _viewport.height - _w.padding.top - _w.padding.bottom) * 0.9
        let y = down ? rect.bottom + step : rect.top - step
        if y < 0 {
            _controller.moveTo(.start, extend: extend)
        } else if y >= _layout.totalHeight {
            _controller.moveTo(_controller.document.endPosition, extend: extend)
        } else {
            _controller.moveTo(_layout.position(at: Offset(x, y), _controller.document), extend: extend)
        }
        _scrollY += down ? step : -step
        _clampScroll()
        // (The view goes a screenful on only as far as the caret can
        // follow: on a page whose text ends near its top, Page Down left
        // the caret behind and showed the blank paper under it — seen
        // 2026-10-13 with two one-page documents.)
        _ensureCaretVisible()
    }

    private func _syncLayoutIfNeeded() {
        if _controller.hasPendingChanges || _layout.count != _controller.document.paragraphs.count {
            _syncLayout()
        }
        if _layout.width > 0 { _layout.ensureLaidOut(_controller.document) }
    }

    /// The misspelled word under the caret, once its paragraph was checked.
    public func misspelling(at pos: RichPosition) -> Range<Int>? {
        _layout.misspelling(at: pos, _controller.document)
    }

    // MARK: Clipboard

    private func _copy() {
        if let data = _controller.copySelectionData() {
            Clipboard.setData(data)
        }
    }

    private func _cut() {
        if let data = _controller.cutSelectionData() {
            Clipboard.setData(data)
        }
    }

    /// ⌘⇧V: the clipboard's text, in the style at the caret.
    private func _pastePlain() {
        Clipboard.getData(Clipboard.kTextPlain) { [weak self] data in
            guard let self, let text = data?.text, !text.isEmpty else { return }
            DispatchQueue.main.async {
                self._controller.insertText(text.replacingAll("\r\n", with: "\n"))
            }
        }
    }

    public func pastePlain() { _pastePlain() }
    public func paste() { _paste() }
    public func copy() { _copy() }
    public func cut() { _cut() }

    private func _paste() {
        Clipboard.getData(Clipboard.kAll) { [weak self] data in
            guard let self, let data, !data.isEmpty else { return }
            if data.rtf != nil || data.html != nil || data.png != nil {
                self._controller.paste(data: data)
                return
            }
            guard let text = data.text, !text.isEmpty else { return }
            DispatchQueue.main.async {
                self._controller.paste(text: text.replacingAll("\r\n", with: "\n"))
            }
        }
    }

    // MARK: Pointer

    private func _canvasPoint(_ local: Offset) -> Offset {
        Offset(local.dx - _originX, local.dy + _scrollY - _w.padding.top)
    }

    /// The two ends of a touch selection as caret boxes in the editable's own
    /// coordinates; nil unless the last touch was a finger and text is selected.
    private func _selectionEnds() -> (start: Rect, end: Rect)? {
        guard _touchMode, _focus.hasFocus, _layout.width > 0, _layout.count > 0 else { return nil }
        let sel = _controller.selection
        guard !sel.isCollapsed, sel.block == nil, _controller.selectedImageIndex == nil else { return nil }
        _syncLayoutIfNeeded()
        func box(_ p: RichPosition) -> Rect {
            let c = _layout.canvasCaretRect(p, _controller.document)
            return Rect.fromLTWH(c.left + _originX, c.top + _w.padding.top - _scrollY, max(c.width, 2), c.height)
        }
        return (box(sel.start), box(sel.end))
    }

    /// The caret's box when its knob is showing (a finger placed it).
    private func _caretHandleBox() -> Rect? {
        guard _touchMode, _caretHandleShown, _focus.hasFocus, !_controller.readOnly, _layout.width > 0, _layout.count > 0 else { return nil }
        let sel = _controller.selection
        guard sel.isCollapsed, sel.block == nil, _controller.selectedImageIndex == nil else { return nil }
        _syncLayoutIfNeeded()
        let c = _layout.canvasCaretRect(sel.focus, _controller.document)
        return Rect.fromLTWH(c.left + _originX, c.top + _w.padding.top - _scrollY, max(c.width, 2), c.height)
    }

    private func _caretHandleHit(_ p: Offset) -> Bool {
        guard let r = _caretHandleBox() else { return false }
        let c = Offset(r.left, r.bottom + Self.knobRadius)
        return abs(p.dx - c.dx) <= 22 && p.dy >= r.top && p.dy <= c.dy + 22
    }

    /// Which end a finger at `p` is holding: 0 the start, 1 the end. The
    /// reach is a fingertip, below the caret where the knob hangs.
    private func _selectionHandleHit(_ p: Offset) -> Int? {
        guard let ends = _selectionEnds() else { return nil }
        var best: (k: Int, d: Double)? = nil
        for (k, r) in [ends.start, ends.end].enumerated() {
            let c = Offset(r.left, r.bottom + Self.knobRadius)
            guard abs(p.dx - c.dx) <= 22, p.dy >= r.top, p.dy <= c.dy + 22 else { continue }
            let d = abs(p.dx - c.dx) + abs(p.dy - c.dy)
            if best == nil || d < best!.d { best = (k, d) }
        }
        return best?.k
    }

    /// Asks the host for the edit menu at the selection (or the caret), or
    /// takes it away. The rect is clipped to what is on screen.
    private func _touchMenu(_ show: Bool) {
        guard let callback = _w.onTouchMenu else { return }
        guard show, _layout.width > 0, _layout.count > 0, let box = context?.findRenderObject() as? RenderBox else {
            callback(nil)
            return
        }
        _syncLayoutIfNeeded()
        let sel = _controller.selection
        var rects = sel.isCollapsed ? [] : _layout.canvasSelectionRects(sel, _controller.document)
        if rects.isEmpty { rects = [_layout.canvasCaretRect(sel.focus, _controller.document)] }
        var r = rects[0]
        for q in rects.dropFirst() { r = Rect.fromLTRB(min(r.left, q.left), min(r.top, q.top), max(r.right, q.right), max(r.bottom, q.bottom)) }
        let local = Rect.fromLTWH(r.left + _originX, r.top + _w.padding.top - _scrollY, max(r.width, 2), r.height)
        let view = Rect.fromLTWH(0, 0, _viewport.width, _viewport.height)
        let l = max(local.left, view.left), t = max(local.top, view.top)
        let rr = min(local.right, view.right), b = min(local.bottom, view.bottom)
        guard rr > l, b > t else { callback(nil); return }
        let o = box.localToGlobal(Offset(l, t))
        callback(Rect.fromLTWH(o.dx, o.dy, rr - l, b - t))
    }

    /// A finger held still on text: the word under it is selected.
    private func _longPress(_ generation: Int, _ at: Offset, _ global: Offset) {
        guard generation == _longPressGen, let t = _touchScroll, !t.moved, _layout.width > 0 else { return }
        _longPressed = true
        _focus.requestFocus()
        _textInput?.show()
        _syncLayoutIfNeeded()
        _controller.selectWord(at: _layout.canvasPosition(at: _canvasPoint(at), _controller.document))
        // A picture set in a line of text is selected, as a click on it does; one of its own is selected by the caret.
        if let hit = _inlineImage(at: at) { _controller.selectInlineImage(in: hit.paragraph, id: hit.id) }
        if _controller.hasSelection { _w.onSelectionGestureEnd?() }
        _repaint.notifyListeners()
        // The same menu a right click opens (text, a table cell, a picture); a host without one gets the edit menu.
        if let menu = _w.onContextMenu { menu(global) } else { _touchMenu(true) }
    }

    /// The right-click menu at `global` for what is under `local`: inside the selection it is about the selection,
    /// elsewhere the caret goes there first, as Word does.
    private func _openContextMenu(local: Offset, global: Offset) {
        _focus.requestFocus()
        if _layout.width > 0 {
            _syncLayoutIfNeeded()
            let pos = _layout.canvasPosition(at: _canvasPoint(local), _controller.document)
            if !_controller.hasSelection || pos < _controller.selection.start || pos > _controller.selection.end {
                _controller.moveTo(pos, extend: false)
                if let hit = _inlineImage(at: local) { _controller.selectInlineImage(in: hit.paragraph, id: hit.id) }
            }
        }
        _w.onContextMenu?(global)
    }

    /// The selected picture's box in the editable's own coordinates, with
    /// the live drag size when one is under way.
    private func _selectedImageBox(group: Bool = false) -> (index: Int, rect: Rect, inline: String?)? {
        if _layout.width > 0 { _syncLayoutIfNeeded() }
        guard _layout.width > 0 else { return nil }
        var canvas: Rect
        var index: Int
        var inline: String? = nil
        if let i = _controller.selectedImageIndex, let flow = _layout.imageRect(i), let c = _layout.canvasRects(flow).first {
            canvas = c; index = i
        } else if let hit = _controller.selectedInlineImage,
                  let c = _layout.canvasSelectionRects(_controller.selection, _controller.document).first {
            // (A picture set in a line of text: the box its character takes; one that floats, the box it is drawn in.)
            canvas = _layout.inlineFloatRect(hit.paragraph, id: hit.id).flatMap { _layout.canvasRects($0).first } ?? c
            index = hit.paragraph; inline = hit.id
        } else { return nil }
        var rect = Rect.fromLTWH(canvas.left + _originX, canvas.top + _w.padding.top - _scrollY,
                                 canvas.width, canvas.height)
        if !group, inline == nil, let k = _controller.groupChild, let boxes = _controller.groupChildBoxes(at: index), boxes.indices.contains(k) {
            // A picked child of a group: its own box (handles, drag and size follow it, not the group).
            let pt = _layout.theme.pixelsPerPoint * _layout.scale, c = boxes[k]
            rect = Rect.fromLTWH(rect.left + c.left * pt, rect.top + c.top * pt, c.width * pt, c.height * pt)
        }
        if let d = _dragSize, !(group && _controller.groupChild != nil) { rect = Rect.fromLTWH(rect.left, rect.top, d.width, d.height) }
        if let d = _moveDelta, !(group && _controller.groupChild != nil) { rect = rect.shift(d) }
        return (index, rect, inline)
    }

    /// The floating picture of its own paragraph under the point (editable coordinates), if any: it is drawn away from
    /// its paragraph, so a press there lands on other text; the paragraph's index.
    private func _floatingImage(at local: Offset) -> Int? {
        guard _layout.width > 0 else { return nil }
        _syncLayoutIfNeeded()
        let canvasPoint = _canvasPoint(local)
        let doc = _controller.document
        for i in doc.paragraphs.indices.reversed() where doc.paragraphs[i].isImage && _controller.pictureWrap(at: i) != nil {
            if let flow = _layout.imageRect(i), _layout.canvasRects(flow).contains(where: { $0.contains(canvasPoint) }) { return i }
        }
        return nil
    }

    /// The picture set in a line of text under the point (editable coordinates), if any.
    private func _inlineImage(at local: Offset) -> (paragraph: Int, id: String)? {
        guard _layout.width > 0 else { return nil }
        let doc = _controller.document
        let pos = _layout.canvasPosition(at: _canvasPoint(local), doc)
        let canvasPoint = _canvasPoint(local)
        // A picture that floats clear of the text is hit where it is drawn, not at its anchor mark.
        for (k, p) in doc.paragraphs.enumerated() where !p.inlineImages.isEmpty {
            for (_, id) in _controller.inlineImageOffsets(in: k) where p.inlineImages[id]?.float != nil {
                if let r = _layout.inlineFloatRect(k, id: id), r.contains(canvasPoint) { return (k, id) }
            }
        }
        for (offset, id) in _controller.inlineImageOffsets(in: pos.paragraph) where abs(offset - pos.offset) <= 1 {
            let sel = RichSelection(anchor: RichPosition(paragraph: pos.paragraph, offset: offset),
                                    focus: RichPosition(paragraph: pos.paragraph, offset: offset + 1))
            if _layout.canvasSelectionRects(sel, doc).contains(where: { $0.contains(canvasPoint) }) { return (pos.paragraph, id) }
        }
        return nil
    }

    /// Handle centres, clockwise from the top-left corner: 0 TL, 1 T, 2 TR,
    /// 3 R, 4 BR, 5 B, 6 BL, 7 L.
    private static func _handles(_ r: Rect) -> [Offset] {
        [Offset(r.left, r.top), Offset(r.center.dx, r.top), Offset(r.right, r.top), Offset(r.right, r.center.dy),
         Offset(r.right, r.bottom), Offset(r.center.dx, r.bottom), Offset(r.left, r.bottom), Offset(r.left, r.center.dy)]
    }

    private func _handleHit(_ p: Offset, _ rect: Rect) -> Int? {
        // A finger's reach is wider than a pointer's, kept to a quarter of the picture's short side so that
        // neighbouring handles (half that apart) never share it.
        let reach = _touchMode ? max(Self.handleSize, min(22, min(rect.width, rect.height) / 4)) : Self.handleSize
        for (k, c) in Self._handles(rect).enumerated() where abs(p.dx - c.dx) <= reach && abs(p.dy - c.dy) <= reach {
            return k
        }
        return nil
    }

    private static func _cursor(forHandle k: Int) -> MouseCursor {
        switch k {
        case 0, 4: return SystemMouseCursors.resizeUpLeftDownRight
        case 2, 6: return SystemMouseCursors.resizeUpRightDownLeft
        case 1, 5: return SystemMouseCursors.resizeUpDown
        default: return SystemMouseCursors.resizeLeftRight
        }
    }

    /// The content-control check box under `local`, as (paragraph, control id): the point is over the glyph itself.
    private func _checkBox(at local: Offset) -> (paragraph: Int, id: Int)? {
        guard _layout.width > 0, _layout.count > 0 else { return nil }
        _syncLayoutIfNeeded()
        let doc = _controller.document
        let flow = _layout.flowPoint(_canvasPoint(local))
        let pos = _layout.canvasPosition(at: _canvasPoint(local), doc)
        guard pos.paragraph < doc.paragraphs.count, !doc.paragraphs[pos.paragraph].isImage else { return nil }
        for box in doc.paragraphs[pos.paragraph].checkBoxes {
            let l = _layout.caretRect(RichPosition(paragraph: pos.paragraph, offset: box.range.lowerBound), doc)
            let r = _layout.caretRect(RichPosition(paragraph: pos.paragraph, offset: box.range.upperBound), doc)
            if flow.dx >= l.left - 1, flow.dx <= r.left + 1, flow.dy >= l.top, flow.dy <= l.top + l.height { return (pos.paragraph, box.id) }
        }
        return nil
    }

    /// The note on the page under a point (its box in the editable's coordinates), if the page has painted one there.
    private func _noteBox(at local: Offset) -> (NoteReference, Rect)? {
        guard _w.onNoteActivate != nil, _layout.width > 0 else { return nil }
        let p = _canvasPoint(local)
        for (id, r) in _layout.noteRects where r.contains(p) {
            return (NoteReference(kind: .footnote, id: id), Rect.fromLTWH(r.left + _originX, r.top + _w.padding.top - _scrollY, r.width, r.height))
        }
        return nil
    }

    /// The note whose mark is at a body position, with the mark's box.
    private func _noteMark(at pos: RichPosition) -> NoteReference? {
        let doc = _controller.document
        guard pos.paragraph < doc.paragraphs.count, !doc.paragraphs[pos.paragraph].isImage else { return nil }
        let para = doc.paragraphs[pos.paragraph]
        for o in [pos.offset, pos.offset - 1] where o >= 0 && o < para.length {
            if let n = para.style(at: o + 1).note { return n }
        }
        return nil
    }

    /// The link at a point in the editable, if the text there carries one.
    private func _link(at local: Offset) -> String? {
        guard _layout.width > 0, _layout.count > 0 else { return nil }
        _syncLayoutIfNeeded()
        let pos = _layout.canvasPosition(at: _canvasPoint(local), _controller.document)
        let para = _controller.document.paragraphs[pos.paragraph]
        guard !para.isImage, pos.offset < para.length else { return nil }
        // Only when the point is actually on the line's text, not past its end.
        let rect = _layout.caretRect(pos, _controller.document)
        let (_, lineEnd) = _layout.lineBounds(pos, _controller.document)
        let endRect = _layout.caretRect(RichPosition(paragraph: pos.paragraph, offset: lineEnd), _controller.document)
        // Caret rectangles use text-flow coordinates; the canvas also
        // includes page margins and the column's horizontal offset.
        let x = _layout.flowPoint(_canvasPoint(local)).dx
        guard x <= endRect.left, x >= rect.left - 2 || pos.offset > 0 else { return nil }
        return para.style(at: pos.offset + 1).link
    }

    private func _pointerHover(_ event: PointerEvent) {
        var handle: Int? = nil
        var overImage = false
        if let box = _selectedImageBox() {
            handle = _handleHit(event.localPosition, box.rect)
            overImage = handle == nil && box.rect.contains(event.localPosition)
        }
        let border = handle == nil && !overImage && _layout.width > 0
            && _layout.columnBorder(at: _layout.flowPoint(_canvasPoint(event.localPosition))) != nil
        if border != _hoverColumnBorder { setState { _hoverColumnBorder = border } }
        let rowEdge = handle == nil && !overImage && !border && _layout.width > 0
            && _layout.rowBorder(at: _layout.flowPoint(_canvasPoint(event.localPosition))) != nil
        if rowEdge != _hoverRowBorder { setState { _hoverRowBorder = rowEdge } }
        let link = handle == nil && !overImage && !border && !rowEdge ? _link(at: event.localPosition) : nil
        let linkChanged = (link != nil) != (_hoverLink != nil)
        if link != _hoverLink {
            _hoverLink = link
            _w.onLinkHover?(link)
        }
        // Rebuild only when the cursor would change; a hover is a stream.
        if handle != _hoverHandle || overImage != _hoverOverImage || linkChanged {
            setState { _hoverHandle = handle; _hoverOverImage = overImage }
        }
    }

    /// A cancelled pointer (the window lost the pointer mid-press) ends
    /// every drag; nothing from it may hijack the next gesture.
    private func _pointerCancel(_ event: PointerEvent) {
        _fingers[event.pointer] = nil
        if _fingers.isEmpty { _twoFingerActive = false }
        _twoFinger = nil
        let hadDrop = _dropPosition != nil || _columnDragWidths != nil || _rowDragHeight != nil || _dragSize != nil
        _dragging = false
        _touchScroll = nil
        _selHandle = nil
        _loupeAt = nil
        _longPressed = false
        _longPressGen += 1
        _unitDrag = nil
        _textDrag = nil
        _dropPosition = nil
        _handleDrag = nil
        _dragSize = nil
        _moveDrag = nil
        _moveDelta = nil
        if let drag = _columnDrag {
            _columnDrag = nil
            _columnDragWidths = nil
            _layout.previewColumns(drag.table, nil, _controller.document)
        }
        if _rowDrag != nil { _rowDrag = nil; _rowDragHeight = nil; _repaint.notifyListeners() }
        if hadDrop { _repaint.notifyListeners() }
    }

    private func _pointerDown(_ event: PointerEvent) {
        _textDrag = nil
        _dropPosition = nil
        _touchMode = event.kind == .touch
        if _w.onDrawTable != nil, event.kind == .touch || event.buttons & 1 != 0 {
            _syncLayoutIfNeeded()
            _drawFrom = (event.localPosition, _layout.cellContaining(_layout.flowPoint(_canvasPoint(event.localPosition))))
            return
        }
        // The border pen or eraser: a press draws, whatever the pointer (a finger included).
        if _w.onCellEdge != nil, event.kind == .touch || event.buttons & 1 != 0 {
            _edgeStroke = nil
            _edgeLast = nil
            _w.onCellEdgeStroke?(true)
            _edgeToolAlong(event.localPosition)
            _edgeDragging = true
            return
        }
        if event.kind == .touch {
            _momentumGeneration += 1   // a glide in progress stops under it
            _touchMenu(false)
            _fingers[event.pointer] = (event.localPosition, event.position)
            if _fingers.count >= 2 {
                // A second finger: what the first began (a scroll, a long press) is abandoned; if both lift in place
                // soon, it was a two-finger tap.
                _longPressGen += 1
                _touchScroll = nil
                _selHandle = nil
                _dragging = false
                _longPressed = false
                if _fingers.count == 2, !_twoFingerActive, let first = _fingers.first(where: { $0.key != event.pointer })?.value {
                    _twoFinger = (Date().timeIntervalSince1970, first.local, first.global)
                } else {
                    _twoFinger = nil
                }
                _twoFingerActive = true
                return
            }
            if let k = _selectionHandleHit(event.localPosition), let ends = _selectionEnds() {
                // A selection handle: the far end stays, the finger moves this one.
                let sel = _controller.selection
                let grabbed = k == 0 ? ends.start : ends.end
                _selHandle = (k == 0 ? sel.end : sel.start, event.localPosition.dy - (grabbed.top + grabbed.height / 2), false)
                _touchScroll = nil
                _dragging = false
                return
            }
            if _caretHandleHit(event.localPosition), let box = _caretHandleBox() {
                // The caret's own knob: the finger moves the caret.
                _selHandle = (nil, event.localPosition.dy - (box.top + box.height / 2), false)
                _touchScroll = nil
                _dragging = false
                return
            }
            if let box = _selectedImageBox(), let k = _handleHit(event.localPosition, box.rect) {
                // A selected picture's size handle: the finger resizes it, as a mouse does.
                _handleDrag = (box.index, k, event.localPosition, box.rect.size, box.inline)
                _dragSize = box.rect.size
                _touchScroll = nil
                _dragging = false
                return
            }
            if let box = _selectedImageBox(group: true), box.rect.contains(event.localPosition),
               _controller.pictureWrap(at: box.index, inline: box.inline) != nil {
                // The body of a selected floating picture: the finger moves it, as a mouse does (a tap that does not travel
                // is still a tap: a text box opens for editing).
                _moveDrag = (box.index, box.inline, event.localPosition)
                _moveDelta = Offset(0, 0)
                _touchScroll = nil
                _dragging = false
                return
            }
            // A finger scrolls; whether it was a tap (or a long press) is known later.
            _longPressed = false
            _longPressGen += 1
            let generation = _longPressGen, downAt = event.localPosition
            let downGlobal = event.position
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?._longPress(generation, downAt, downGlobal) }
            _touchScroll = (event.localPosition.dy, _scrollY, event.localPosition.dy, Date().timeIntervalSince1970, 0, false)
            _dragging = false
            return
        }
        if event.buttons & kSecondaryButton != 0 {
            // The event's position is already the view's: the menu goes there.
            _openContextMenu(local: event.localPosition, global: event.position)
            return
        }
        if _controller.pendingShape != nil, !_controller.readOnly, event.buttons & 1 != 0, _layout.width > 0 {
            _focus.requestFocus()
            _shapeDraw = (event.localPosition, event.localPosition)
            _dragging = false
            return
        }
        // ⌘-click follows a link while editing, as Word does; reading, a
        // plain click does, as a page does.
        if _chords.primary || _controller.readOnly, let link = _link(at: event.localPosition) {
            if let activate = _w.onLinkActivate { activate(link) } else { hostOpenURL?(link) }
            return
        }
        // A click on a check box control flips it, as Word does.
        if !_controller.readOnly, !_chords.shift, let box = _checkBox(at: event.localPosition) {
            _focus.requestFocus()
            _controller.toggleCheckBox(in: box.paragraph, control: box.id)
            return
        }
        if _chords.primary, !_chords.shift, event.buttons & 1 != 0, _layout.width > 0 {
            // ⌘-click selects the sentence, as in Word.
            _focus.requestFocus()
            _syncLayoutIfNeeded()
            _controller.selectSentence(at: _layout.canvasPosition(at: _canvasPoint(event.localPosition), _controller.document))
            if _controller.hasSelection { _w.onSelectionGestureEnd?() }
            return
        }

        if _chords.shift || _controller.selectMultiple, !_controller.readOnly, event.buttons & 1 != 0, _controller.selectedImageIndex != nil, let hit = _floatingImage(at: event.localPosition),
           hit != _controller.selectedImageIndex {
            // Shift-click on another floating shape: picks it along with the selected one, to group them.
            _focus.requestFocus()
            _controller.toggleShapePick(at: hit)
            return
        }

        if let box = _selectedImageBox(group: true), _handleHit(event.localPosition, _selectedImageBox()?.rect ?? box.rect) == nil, box.rect.contains(event.localPosition),
           _controller.pictureWrap(at: box.index, inline: box.inline) != nil {
            // The body of a selected floating picture: pressed and dragged, it moves.
            _moveDrag = (box.index, box.inline, event.localPosition)
            _moveDelta = Offset(0, 0)
            _dragging = false
            return
        }
        if let box = _selectedImageBox(), let k = _handleHit(event.localPosition, box.rect) {
            _handleDrag = (box.index, k, event.localPosition, box.rect.size, box.inline)
            _dragSize = box.rect.size
            _dragging = false
            return
        }
        if _layout.width > 0, let border = _layout.columnBorder(at: _layout.flowPoint(_canvasPoint(event.localPosition))),
           let widths = _layout.columnWidths(of: border.table) {
            let pt = _layout.theme.pixelsPerPoint * _layout.scale
            _columnDrag = (border.table, border.column, event.localPosition.dx / pt, widths)
            _dragging = false
            return
        }
        if _layout.width > 0, let edge = _layout.rowBorder(at: _layout.flowPoint(_canvasPoint(event.localPosition))) {
            let pt = _layout.theme.pixelsPerPoint * _layout.scale
            let canvas = _canvasPoint(event.localPosition)
            _rowDrag = (edge.table, edge.row, event.localPosition.dy / pt, edge.height, canvas.dy, edge.left, edge.right, canvas.dx)
            _rowDragHeight = edge.height
            _dragging = false
            return
        }
        _focus.requestFocus()
        _textInput?.show()
        guard event.buttons & 1 != 0 else { return }
        _syncLayoutIfNeeded()
        guard _layout.width > 0 else { return }
        if !_controller.readOnly, !_chords.shift, let (n, box) = _noteBox(at: event.localPosition) {
            _w.onNoteActivate?(n, box.shift( Offset(event.position.dx - event.localPosition.dx, event.position.dy - event.localPosition.dy)))
            return
        }
        let now = Date().timeIntervalSince1970
        let near = abs(event.localPosition.dx - _lastClickPos.dx) < 6
            && abs(event.localPosition.dy - _lastClickPos.dy) < 6
        _clickStreak = (now - _lastClickAt < 0.45 && near) ? _clickStreak + 1 : 1
        _lastClickAt = now
        _lastClickPos = event.localPosition
        let pos = _layout.canvasPosition(at: _canvasPoint(event.localPosition), _controller.document)
        _stickyX = nil
        switch _clickStreak {
        case 1:
            let sel = _controller.selection
            if !_chords.shift, _controller.hasSelection, sel.block == nil,
               pos > sel.start, pos < sel.end, _controller.selectedImageIndex == nil, _controller.selectedInlineImage == nil {
                // Pressing on selected text starts a drag of it, not a new
                // selection; the caret moves only if the press stays put.
                _textDrag = (event.localPosition, false)
                _dragging = false
                return
            }
            _dragging = true
            _controller.moveTo(pos, extend: _chords.shift)
            // A click on a picture set in a line of text selects it (with its handles), as on a picture of its own.
            if !_chords.shift, let hit = _inlineImage(at: event.localPosition) {
                _controller.selectInlineImage(in: hit.paragraph, id: hit.id)
                _dragging = false
            } else if !_chords.shift, let i = _floatingImage(at: event.localPosition), _controller.pictureWrap(at: i)?.behind != true {
                // A box or picture floating over the text (as boxes from an opened file do) is hit where it is drawn,
                // not through to the line under it, as a tap does. One behind the text leaves the click to the words.
                _controller.selectImage(at: i)
                _dragging = false
            }
        case 2:
            if !_controller.readOnly, let activate = _w.onNoteActivate, let n = _noteMark(at: pos) {
                _dragging = false
                let r = _layout.noteRects[n.id] ?? _layout.caretRect(pos, _controller.document)
                activate(n, Rect.fromLTWH(r.left + _originX + event.position.dx - event.localPosition.dx, r.top + _w.padding.top - _scrollY + event.position.dy - event.localPosition.dy,
                                          max(r.width, 200), max(r.height, 20)))
                return
            }
            if let edit = _w.onHeaderFooterEdit,
               let kind = _layout.headerFooterZone(atCanvas: _canvasPoint(event.localPosition), _controller.document) {
                _dragging = false
                edit(kind)
                return
            }
            _controller.selectWord(at: pos)
            _dragging = true
            _unitDrag = (_controller.selection, false)
        default:
            _controller.selectParagraph(at: pos)
            _dragging = true
            _unitDrag = (_controller.selection, true)
        }
    }

    private func _pointerMove(_ event: PointerEvent) {
        if _drawFrom != nil { return }
        if _edgeDragging, _w.onCellEdge != nil { _edgeToolAlong(event.localPosition); return }
        if event.kind == .touch, _twoFingerActive {
            // Two fingers are down: a tap only while neither travels.
            if let start = _fingers[event.pointer]?.local,
               abs(event.localPosition.dx - start.dx) > 12 || abs(event.localPosition.dy - start.dy) > 12 {
                _twoFinger = nil
            }
            return
        }
        if let h = _selHandle, _layout.width > 0 {
            // The finger holds the knob below the line; the position is the line it is on.
            let y = event.localPosition.dy
            if y < 30 { _scrollY -= 12 } else if y > _viewport.height - 30 { _scrollY += 12 }
            _clampScroll()
            let pos = _layout.canvasPosition(at: _canvasPoint(Offset(event.localPosition.dx, y - h.grabDY)), _controller.document)
            if let fixed = h.fixed {
                _controller.selection = RichSelection(anchor: fixed, focus: pos)
            } else {
                _controller.moveTo(pos, extend: false)
            }
            _selHandle?.moved = true
            _loupeAt = event.localPosition
            _repaint.notifyListeners()
            return
        }
        if var t = _touchScroll {
            if _longPressed { return }   // held to select: the finger no longer scrolls
            let y = event.localPosition.dy
            let now = Date().timeIntervalSince1970
            if !t.moved, abs(y - t.startY) > 8 {
                // Past the tap slop: the scroll starts from here, no jump.
                t.moved = true
                t.startY = y
                t.scrollStart = _scrollY
            }
            if t.moved {
                let before = _scrollY
                _scrollY = t.scrollStart - (y - t.startY)
                _clampScroll()
                let dt = max(0.001, now - t.lastTime)
                let perFrame = -(y - t.lastY) / dt * 0.016
                t.velocity = t.velocity * 0.4 + perFrame * 0.6
                if _scrollY != before { _repaint.notifyListeners() }
            }
            t.lastY = y
            t.lastTime = now
            _touchScroll = t
            return
        }
        if let drag = _textDrag {
            guard event.buttons & 1 != 0, _layout.width > 0 else { return }
            if !drag.active {
                let moved = abs(event.localPosition.dx - drag.start.dx) > 4 || abs(event.localPosition.dy - drag.start.dy) > 4
                guard moved else { return }
                setState { _textDrag = (drag.start, true) }   // the cursor changes
            }
            let y = event.localPosition.dy
            if y < 0 { _scrollY -= min(40, -y) } else if y > _viewport.height { _scrollY += min(40, y - _viewport.height) }
            _clampScroll()
            let pos = _layout.canvasPosition(at: _canvasPoint(event.localPosition), _controller.document)
            if pos != _dropPosition {
                _dropPosition = pos
                _repaint.notifyListeners()
            }
            return
        }
        if let drag = _columnDrag {
            // The dragged edge moves; the next column gives or takes the
            // difference so the table keeps its width, the last column
            // just grows or shrinks. Nothing narrower than 12pt.
            let pt = _layout.theme.pixelsPerPoint * _layout.scale
            var dx = event.localPosition.dx / pt - drag.startX
            var w = drag.widths
            let k = drag.column
            let hasNext = k + 1 < w.count
            dx = max(dx, 12 - w[k])
            if hasNext { dx = min(dx, w[k + 1] - 12) }
            else { dx = min(dx, _layout.width / pt - w.reduce(0, +)) }
            w[k] += dx
            if hasNext { w[k + 1] -= dx }
            _columnDragWidths = w
            _layout.previewColumns(drag.table, w, _controller.document)
            _repaint.notifyListeners()
            return
        }
        if _shapeDraw != nil {
            _shapeDraw?.now = event.localPosition
            return
        }
        if let drag = _moveDrag {
            _moveDelta = Offset(event.localPosition.dx - drag.start.dx, event.localPosition.dy - drag.start.dy)
            _repaint.notifyListeners()
            return
        }
        if let drag = _rowDrag {
            // The row's bottom border follows the pointer; a guide line shows where it will land. Never under 6 pt.
            let pt = _layout.theme.pixelsPerPoint * _layout.scale
            _rowDragHeight = max(6, drag.height + event.localPosition.dy / pt - drag.startY)
            _repaint.notifyListeners()
            return
        }
        if let drag = _handleDrag {
            // Corners keep the aspect; edges are free. Never below 8px,
            // never wider than the column.
            let dx = event.localPosition.dx - drag.start.dx
            let dy = event.localPosition.dy - drag.start.dy
            let sx: Double = [2, 3, 4].contains(drag.handle) ? 1 : [0, 6, 7].contains(drag.handle) ? -1 : 0
            let sy: Double = [4, 5, 6].contains(drag.handle) ? 1 : [0, 1, 2].contains(drag.handle) ? -1 : 0
            var w = drag.size.width + sx * dx
            var h = drag.size.height + sy * dy
            let corner = drag.handle % 2 == 0
            if corner {
                let scale = max(w / drag.size.width, h / drag.size.height)
                w = drag.size.width * scale
                h = drag.size.height * scale
            }
            let maxW = _layout.width
            if w > maxW { if corner { h *= maxW / w }; w = maxW }
            w = max(8, w); h = max(8, h)
            _dragSize = Size(w.rounded(), h.rounded())
            _repaint.notifyListeners()
            return
        }
        guard _dragging, event.buttons & 1 != 0, _layout.width > 0 else { return }
        // Autoscroll when dragging past the edges.
        let y = event.localPosition.dy
        if y < 0 { _scrollY -= min(40, -y) } else if y > _viewport.height { _scrollY += min(40, y - _viewport.height) }
        _clampScroll()
        let pos = _layout.canvasPosition(at: _canvasPoint(event.localPosition), _controller.document)
        if let unit = _unitDrag {
            _controller.extendSelection(to: pos, byParagraph: unit.paragraphs, from: unit.origin)
        } else {
            _controller.moveTo(pos, extend: true)
        }
    }

    private func _pointerUp(_ event: PointerEvent) {
        if let d = _drawFrom {
            _drawFrom = nil
            _w.onDrawTable?(d.cell, event.localPosition.dx - d.local.dx, event.localPosition.dy - d.local.dy)
            return
        }
        if _edgeDragging { _edgeDragging = false; _edgeStroke = nil; _edgeLast = nil; _w.onCellEdgeStroke?(false); return }
        if event.kind == .touch {
            _fingers[event.pointer] = nil
            if _twoFingerActive {
                if _fingers.isEmpty {
                    _twoFingerActive = false
                    if let two = _twoFinger, Date().timeIntervalSince1970 - two.at < 0.6 {
                        _twoFinger = nil
                        _openContextMenu(local: two.local, global: two.global)
                    }
                    _twoFinger = nil
                }
                return
            }
        }
        if let h = _selHandle {
            _selHandle = nil
            _loupeAt = nil
            _w.onSelectionGestureEnd?()
            _repaint.notifyListeners()
            // A dragged caret just stays; a tap on its knob, or a range handle, asks for the menu.
            if h.fixed != nil || !h.moved { _touchMenu(true) }
            return
        }
        if let t = _touchScroll {
            _touchScroll = nil
            _longPressGen += 1
            if _longPressed { _longPressed = false; return }
            if t.moved {
                if abs(t.velocity) > 1 {
                    _momentumGeneration += 1
                    _glide(_momentumGeneration, velocity: t.velocity)
                }
            } else if _layout.width > 0 {
                // A tap: reading, a link opens; editing, the caret goes there (a finger cannot hover, so the link
                // card the caret under a link raises is how it is opened, edited or removed), as a click does.
                if _controller.readOnly, let link = _link(at: event.localPosition) {
                    if let activate = _w.onLinkActivate { activate(link) } else { hostOpenURL?(link) }
                    return
                }
                if !_controller.readOnly, let box = _checkBox(at: event.localPosition) {
                    _focus.requestFocus()
                    _controller.toggleCheckBox(in: box.paragraph, control: box.id)
                    return
                }
                _syncLayoutIfNeeded()
                if !_controller.readOnly, let (n, box) = _noteBox(at: event.localPosition) {
                    _w.onNoteActivate?(n, box.shift(Offset(event.position.dx - event.localPosition.dx, event.position.dy - event.localPosition.dy)))
                    return
                }
                if _controller.selectMultiple, !_controller.readOnly, _controller.selectedImageIndex != nil,
                   let hit = _floatingImage(at: event.localPosition), hit != _controller.selectedImageIndex {
                    // Select Multiple: a tap on another floating shape picks it along with the selected one (or drops it again).
                    _focus.requestFocus()
                    _controller.toggleShapePick(at: hit)
                    return
                }
                _focus.requestFocus()
                _textInput?.show()
                let pos = _layout.canvasPosition(at: _canvasPoint(event.localPosition), _controller.document)
                let now = Date().timeIntervalSince1970
                let again = now - _lastTap.at < 0.4
                    && abs(event.localPosition.dx - _lastTap.pos.dx) < 24 && abs(event.localPosition.dy - _lastTap.pos.dy) < 24
                if again {
                    // A second tap in the same place: the word.
                    _lastTap = (0, Offset(-100, -100))
                    _controller.selectWord(at: pos)
                    if _controller.hasSelection { _w.onSelectionGestureEnd?() }
                    _touchMenu(true)
                } else {
                    _lastTap = (now, event.localPosition)
                    // A tap on the caret itself asks for the menu, as on iOS text.
                    let onCaret = _controller.selection.isCollapsed && _controller.caret == pos
                    _controller.moveTo(pos, extend: false)
                    _caretHandleShown = true
                    // A tap on a picture set in a line of text, or floating clear of it, selects it (with its handles),
                    // as a click does.
                    if let hit = _inlineImage(at: event.localPosition) {
                        _controller.selectInlineImage(in: hit.paragraph, id: hit.id)
                        _caretHandleShown = false
                    } else if let i = _floatingImage(at: event.localPosition) {
                        _controller.selectImage(at: i)
                        _caretHandleShown = false
                    }
                    if onCaret { _touchMenu(true) }
                }
            }
            return
        }
        if let drag = _textDrag {
            _textDrag = nil
            _dropPosition = nil
            if _layout.width > 0 {
                if drag.active {
                    let pos = _layout.canvasPosition(at: _canvasPoint(event.localPosition), _controller.document)
                    _controller.moveSelection(to: pos, copy: _chords.alt)
                    setState {}   // back to the I-beam
                } else {
                    _controller.moveTo(_layout.canvasPosition(at: _canvasPoint(drag.start), _controller.document), extend: false)
                }
            }
            _repaint.notifyListeners()
            return
        }
        let wasDragging = _dragging
        _dragging = false
        _unitDrag = nil
        if wasDragging { _w.onSelectionGestureEnd?() }   // a bare click too: the painter paints its word
        if let drag = _columnDrag {
            _columnDrag = nil
            let final = _columnDragWidths
            _columnDragWidths = nil
            _layout.previewColumns(drag.table, nil, _controller.document)
            if let final, final != drag.widths {
                _controller.setTableColumnWidths(drag.table, final)
            } else {
                // No edit follows to re-lay the table out: do it now, or a
                // hover before the next paint finds no painters.
                _syncLayoutIfNeeded()
            }
            _repaint.notifyListeners()
            return
        }

        if let draw = _shapeDraw {
            _shapeDraw = nil
            _syncLayoutIfNeeded()
            let a = _canvasPoint(draw.start), b = _canvasPoint(draw.now)
            let page = _layout.page(atCanvasY: a.dy), origin = _layout.pageRect(page)
            let pt = _layout.theme.pixelsPerPoint * _layout.scale
            // A bare click makes the usual size with its top left corner at the click; a drag makes the box it covers.
            let dragged = abs(b.dx - a.dx) >= 4 * pt && abs(b.dy - a.dy) >= 4 * pt
            let w = dragged ? abs(b.dx - a.dx) / pt : 96, h = dragged ? abs(b.dy - a.dy) / pt : 72
            let x = (min(a.dx, b.dx) - origin.left) / pt, y = (min(a.dy, b.dy) - origin.top) / pt
            _controller.placePendingShape(x: max(0, x.rounded()), y: max(0, y.rounded()), width: w.rounded(), height: h.rounded(),
                                          at: _layout.canvasPosition(at: a, _controller.document))
            _repaint.notifyListeners()
            return
        }
        if let drag = _moveDrag {
            let d = _moveDelta ?? Offset(0, 0)
            _moveDrag = nil
            let box = _selectedImageBox(group: true)
            _moveDelta = nil
            let childRect = _controller.groupChild != nil ? _selectedImageBox()?.rect : nil
            if d.dx == 0, d.dy == 0, drag.inline == nil, let cr = childRect, cr.contains(drag.start), let enter = _w.onTextBoxEnter,
               _controller.groupChildTextDocument() != nil {
                enter(drag.index, nil, cr)   // a second click on the picked child types into it
                return
            }
            if d.dx == 0, d.dy == 0, let box, drag.inline == nil, _controller.groupChildBoxes(at: drag.index) != nil {
                // A click on the selected group goes into it: the child under the point is picked.
                let pt = _layout.theme.pixelsPerPoint * _layout.scale
                _controller.pickGroupChild(at: drag.index, point: Offset((drag.start.dx - box.rect.left) / pt, (drag.start.dy - box.rect.top) / pt))
                _repaint.notifyListeners()
                return
            }
            if d.dx == 0, d.dy == 0, box != nil, _w.onTextBoxEnter != nil, _controller.textBoxDocument(at: drag.index, inline: drag.inline) == nil {
                _controller.giveShapeText(at: drag.index, inline: drag.inline)   // a plain shape takes text when entered
            }
            if d.dx == 0, d.dy == 0, let box, let enter = _w.onTextBoxEnter, _controller.textBoxDocument(at: drag.index, inline: drag.inline) != nil {
                enter(drag.index, drag.inline, box.rect)
                return
            }
            let pt = _layout.theme.pixelsPerPoint * _layout.scale
            if drag.inline == nil, _controller.groupChild != nil, childRect?.contains(drag.start) == true {
                // A child of the group is picked: it moves, the group's other children stay.
                if d.dx != 0 || d.dy != 0 { _controller.editGroupChild(.move(dx: Int((d.dx / pt * 12700).rounded()), dy: Int((d.dy / pt * 12700).rounded()))) }
                _repaint.notifyListeners()
                return
            }
            _controller.movePicture(at: drag.index, inline: drag.inline, dx: (d.dx / pt).rounded(), dy: (d.dy / pt).rounded())
            _repaint.notifyListeners()
            return
        }
        if let drag = _rowDrag {
            _rowDrag = nil
            let final = _rowDragHeight
            _rowDragHeight = nil
            if let final, abs(final - drag.height) >= 0.5 { _controller.setRowHeight(table: drag.table, row: drag.row, points: final) }
            _repaint.notifyListeners()
            return
        }
        if let drag = _handleDrag, let size = _dragSize {
            _handleDrag = nil
            _dragSize = nil
            let pt = _layout.theme.pixelsPerPoint * _layout.scale
            if drag.inline == nil, _controller.groupChild != nil {
                _controller.editGroupChild(.resize(cx: Int((size.width / pt * 12700).rounded()), cy: Int((size.height / pt * 12700).rounded())))
            } else if let id = drag.inline {
                _controller.setInlineImageSize(in: drag.index, id: id, width: size.width / pt, height: size.height / pt)
            } else {
                _controller.setImageSize(at: drag.index, width: size.width / pt, height: size.height / pt)
            }
            _repaint.notifyListeners()
        }
    }

    private func _pointerSignal(_ event: PointerSignalEvent) {
        guard let scroll = event as? PointerScrollEvent else { return }
        _momentumGeneration += 1   // a wheel tick ends any trackpad glide
        let before = _scrollY
        _scrollY += scroll.scrollDelta.dy
        _clampScroll()
        if _scrollY != before { _repaint.notifyListeners() }
    }

    // A trackpad scrolls as a pan gesture on macOS (the embedder sends
    // pan-zoom events for anything with a phase, and drops the system's
    // momentum events for the framework to make its own), so the content
    // follows the fingers here and glides on after they lift.
    private func _panZoomStart(_ event: PointerPanZoomStartEvent) {
        _momentumGeneration += 1
        _panVelocity = 0
        _panLastTime = event.timeStamp
    }

    private func _panZoomUpdate(_ event: PointerPanZoomUpdateEvent) {
        let before = _scrollY
        _scrollY -= event.panDelta.dy
        _clampScroll()
        if let last = _panLastTime {
            let dt = max(1, Double((event.timeStamp - last).components.attoseconds) / 1e15)   // ms
            let perFrame = -event.panDelta.dy / dt * 16
            _panVelocity = _panVelocity * 0.4 + perFrame * 0.6
        }
        _panLastTime = event.timeStamp
        if _scrollY != before { _repaint.notifyListeners() }
    }

    private func _panZoomEnd(_ event: PointerPanZoomEndEvent) {
        _panLastTime = nil
        guard abs(_panVelocity) > 1 else { return }
        _momentumGeneration += 1
        _glide(_momentumGeneration, velocity: _panVelocity)
    }

    private func _glide(_ gen: Int, velocity: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) { [weak self] in
            guard let self, self._momentumGeneration == gen else { return }
            let before = self._scrollY
            self._scrollY += velocity
            self._clampScroll()
            if self._scrollY == before { return }   // hit an end
            self._repaint.notifyListeners()
            let next = velocity * 0.95
            if abs(next) > 0.5 { self._glide(gen, velocity: next) }
        }
    }

    // MARK: Paint

    fileprivate func _paint(_ canvas: any Canvas, _ size: Size) {
        let t0 = Self._perf ? DispatchTime.now().uptimeNanoseconds : 0
        defer {
            if Self._perf {
                let micros = Int((DispatchTime.now().uptimeNanoseconds - t0) / 1000)
                Self._log("richtext: layout \(_lastLayoutMicros)us paint \(micros)us paragraphs \(_layout.count) height \(Int(_layout.totalHeight))")
                _lastLayoutMicros = 0
            }
        }
        _viewport = size
        let pad = _w.padding
        let contentWidth: Double
        if let setup = _w.pageSetup {
            contentWidth = max(1, setup.columnWidth * _layout.theme.pixelsPerPoint * _layout.scale)
        } else {
            contentWidth = max(1, size.width - pad.left - pad.right)
        }
        if _layout.width != contentWidth {
            _layout.width = contentWidth
        }
        _layout.hiddenFrameID = _w.hiddenFrameID
        _syncLayout()
        _clampScroll()
        let canvasW = _layout.canvasSize.width
        _originX = _w.pageSetup == nil ? pad.left : max(pad.left, ((size.width - canvasW) / 2).rounded())

        if let bg = _w.backgroundColor {
            let paint = Paint()
            paint.color = bg
            paint.style = .fill
            canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint)
        }
        canvas.save()
        canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height))
        canvas.translate(_originX, pad.top - _scrollY)
        let visible = Rect.fromLTWH(-_originX, _scrollY - pad.top, size.width, size.height)
        let focused = _focus.hasFocus
        let caretRect = _layout.count > 0 ? _layout.canvasCaretRect(_controller.caret, _controller.document) : nil
        let pageColor = _w.pageColor
        let pageBackground: (Int, Rect) -> Void = { _, rect in
            let shadow = Paint()
            shadow.color = Color(0x22000000)
            shadow.style = .fill
            canvas.drawRect(rect.shift(Offset(0, 2)).inflate(1), shadow)
            let paper = Paint()
            paper.color = pageColor
            paper.style = .fill
            canvas.drawRect(rect, paper)
        }
        _layout.paint(canvas, visible: visible, document: _controller.document,
                      selection: _controller.selection,
                      caret: (focused && _caretVisible && _controller.selection.isCollapsed) ? caretRect : nil,
                      pageBackground: pageBackground)
        // A caret inside a field shades the field gray, as Word does.
        if focused, let field = _controller.fieldRangeAtCaret() {
            let shade = Paint()
            shade.style = .fill
            shade.color = Color(0x30808080)
            for r in _layout.canvasSelectionRects(field, _controller.document) { canvas.drawRect(r, shade) }
        }
        // Paragraphs shown for the first time get checked after an idle,
        // not in the paint: NSSpellChecker takes milliseconds on a bad one.
        if !_layout.pendingSpellChecks.isEmpty, !_spellScheduled {
            _spellScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                self._spellScheduled = false
                if self._layout.runSpellChecks(self._controller.document) { self._repaint.notifyListeners() }
            }
        }
        // Where dragged text will drop: a caret that follows the pointer.
        if let drop = _dropPosition, _layout.count > drop.paragraph {
            let r = _layout.canvasCaretRect(drop, _controller.document)
            let paint = Paint()
            paint.style = .fill
            paint.color = _layout.theme.caretColor
            canvas.drawRRect(RRect(fromRectAndRadius: r, Radius(circular: 1)), paint)
        }
        // A row border being dragged: a guide line where the row's bottom will land.
        if let drag = _rowDrag, let h = _rowDragHeight {
            let pt = _layout.theme.pixelsPerPoint * _layout.scale
            let y = drag.canvasY + (h - drag.height) * pt
            let guide = Paint()
            guide.style = .stroke
            guide.strokeWidth = 1
            guide.color = _layout.theme.caretColor
            canvas.drawLine(Offset(drag.canvasX + drag.left, y), Offset(drag.canvasX + drag.right, y), guide)
        }
        // An IME's uncommitted text: a line under the composing range.
        if let composing = _controller.composingRange, _layout.count > composing.paragraph {
            let sel = RichSelection(anchor: RichPosition(paragraph: composing.paragraph, offset: composing.range.lowerBound),
                                    focus: RichPosition(paragraph: composing.paragraph, offset: composing.range.upperBound))
            let line = Paint()
            line.style = .stroke
            line.strokeWidth = 1
            line.color = _layout.theme.textColor
            for r in _layout.canvasSelectionRects(sel, _controller.document) {
                canvas.drawLine(Offset(r.left, r.bottom - 1.5), Offset(r.right, r.bottom - 1.5), line)
            }
        }
        canvas.restore()
        // The input method's candidate window follows the caret: the
        // plugin gets the caret's box in the editable's own coordinates and
        // the editable's transform to the view (without them it answers
        // the window with a zero rect, which puts the candidates at the
        // screen's bottom-left corner).
        if let input = _textInput, input.isAttached, let c = caretRect,
           let box = context?.findRenderObject() as? RenderBox {
            input.setCaretRect(Rect.fromLTWH(c.left + _originX, c.top + pad.top - _scrollY, c.width, c.height),
                               editableSize: size, transform: TextInputChannel.windowTransform(of: box))
        }

        // A selected picture: its outline and eight handles.
        if focused, let box = _selectedImageBox() {
            let r = box.rect
            let line = Paint()
            line.style = .stroke
            line.strokeWidth = 1
            line.color = _layout.theme.selectionColor.withOpacity(1)
            canvas.drawRect(Rect.fromLTRB(r.left.rounded() + 0.5, r.top.rounded() + 0.5,
                                          r.right.rounded() - 0.5, r.bottom.rounded() - 0.5), line)
            let fill = Paint()
            fill.style = .fill
            fill.color = Color(0xFFFFFFFF)
            let half = Self.handleSize / 2
            for c in Self._handles(r) {
                let h = Rect.fromLTWH(c.dx - half, c.dy - half, Self.handleSize, Self.handleSize)
                canvas.drawRect(h, fill)
                canvas.drawRect(h, line)
            }
        }

        // The child picked inside a selected group: its own outline.
        if focused, let box = _selectedImageBox(group: true), let k = _controller.groupChild, let boxes = _controller.groupChildBoxes(at: box.index), boxes.indices.contains(k) {
            let pt = _layout.theme.pixelsPerPoint * _layout.scale
            let c = boxes[k]
            let line = Paint()
            line.style = .stroke
            line.strokeWidth = 1.5
            line.color = _layout.theme.selectionColor.withOpacity(1)
            let m = _moveDelta ?? Offset(0, 0)
            canvas.drawRect(Rect.fromLTWH(box.rect.left + c.left * pt + m.dx, box.rect.top + c.top * pt + m.dy, c.width * pt, c.height * pt), line)
        }

        // Shapes picked along with it (Shift-click): their outlines.
        if focused, !_controller.shapePicks.isEmpty {
            let line = Paint()
            line.style = .stroke
            line.strokeWidth = 1
            line.color = _layout.theme.selectionColor.withOpacity(1)
            for i in _controller.pickedShapeIndexes where i != _controller.selectedImageIndex {
                guard let flow = _layout.imageRect(i), let c = _layout.canvasRects(flow).first else { continue }
                let r = Rect.fromLTWH(c.left + _originX, c.top + _w.padding.top - _scrollY, c.width, c.height)
                canvas.drawRect(Rect.fromLTRB(r.left.rounded() + 0.5, r.top.rounded() + 0.5, r.right.rounded() - 0.5, r.bottom.rounded() - 0.5), line)
            }
        }

        // A placed caret: a knob under it, to drag.
        if let r = _caretHandleBox() {
            let fill = Paint()
            fill.style = .fill
            fill.color = _layout.theme.selectionColor.withOpacity(1)
            let rim = Paint()
            rim.style = .stroke
            rim.strokeWidth = 1.5
            rim.color = Color(0xFFFFFFFF)
            let k = Self.knobRadius
            let knob = RRect(fromRectAndRadius: Rect.fromLTWH(r.left + r.width / 2 - k, r.bottom, k * 2, k * 2), Radius(circular: k))
            canvas.drawRRect(knob, fill)
            canvas.drawRRect(knob, rim)
        }

        // A touch selection: a stem and a knob at each end, to drag.
        if let ends = _selectionEnds() {
            let fill = Paint()
            fill.style = .fill
            fill.color = _layout.theme.selectionColor.withOpacity(1)
            let rim = Paint()
            rim.style = .stroke
            rim.strokeWidth = 1.5
            rim.color = Color(0xFFFFFFFF)
            let k = Self.knobRadius
            for r in [ends.start, ends.end] {
                canvas.drawRect(Rect.fromLTWH(r.left - 1, r.top, 2, r.height), fill)
                let knob = RRect(fromRectAndRadius: Rect.fromLTWH(r.left - k, r.bottom, k * 2, k * 2), Radius(circular: k))
                canvas.drawRRect(knob, fill)
                canvas.drawRRect(knob, rim)
            }
        }

        // The magnifier over a dragged handle: the same text again, larger, in a
        // circle above the line (below it when the line is at the top edge).
        if let finger = _loupeAt, _selHandle != nil, size.width > 0, _layout.count > 0 {
            let r = Self.loupeRadius, z = Self.loupeZoom
            // What it shows: the caret being dragged, in view coordinates.
            let cb = _layout.canvasCaretRect(_controller.caret, _controller.document)
            let src = Offset(cb.left + _originX, cb.top + cb.height / 2 + pad.top - _scrollY)
            let cx = min(max(finger.dx, r + 4), size.width - r - 4)
            var cy = src.dy - r - 46
            if cy - r < 4 { cy = src.dy + r + 70 }
            let circle = RRect(fromRectAndRadius: Rect.fromLTWH(cx - r, cy - r, r * 2, r * 2), Radius(circular: r))
            let shade = Paint()
            shade.style = .fill
            shade.color = Color(0x30000000)
            canvas.drawCircle(Offset(cx, cy + 2), r + 1, shade)
            canvas.save()
            canvas.clipRRect(circle)
            let back = Paint()
            back.style = .fill
            back.color = _w.backgroundColor ?? Color(0xFFFFFFFF)
            canvas.drawRect(Rect.fromLTWH(cx - r, cy - r, r * 2, r * 2), back)
            canvas.translate(cx, cy)
            canvas.scale(z, z)
            canvas.translate(-src.dx, -src.dy)
            canvas.translate(_originX, pad.top - _scrollY)
            let half = r / z
            let around = Rect.fromLTWH(src.dx - _originX - half, src.dy - pad.top + _scrollY - half, half * 2, half * 2)
            _layout.paint(canvas, visible: around, document: _controller.document,
                          selection: _controller.selection, caret: nil, pageBackground: pageBackground)
            canvas.restore()
            let rim = Paint()
            rim.style = .stroke
            rim.strokeWidth = 2
            rim.color = _layout.theme.selectionColor.withOpacity(1)
            canvas.drawCircle(Offset(cx, cy), r, rim)
        }

        // Scrollbar thumb.
        let total = contentHeight
        if _w.scrolls, total > size.height + 1 {
            let trackH = size.height - 4
            let thumbH = max(24, trackH * size.height / total)
            let thumbY = 2 + (trackH - thumbH) * (_scrollY / max(1, total - size.height))
            let paint = Paint()
            paint.color = Color(0x40808080)
            paint.style = .fill
            canvas.drawRRect(RRect(fromRectAndRadius: Rect.fromLTWH(size.width - 8, thumbY, 6, thumbH),
                                   Radius(circular: 3)), paint)
        }

        if let report = _w.onContentHeight {
            let h = _layout.totalHeight
            if h != _lastContentHeight {
                _lastContentHeight = h
                DispatchQueue.main.async { report(h) }
            }
        }
        if let follow = _w.onBoxRect {
            let r = _selectedImageBox()?.rect
            if r != _lastBoxRect {
                _lastBoxRect = r
                DispatchQueue.main.async { follow(r) }
            }
        }
        if let info = _w.onPageInfo {
            // Editing, the caret's page, as Word's status bar; reading, the
            // page at the top of the view, which is what scrolling changes.
            let now = (_controller.readOnly ? visiblePage : caretPage, pageCount)
            if now != _lastPageInfo {
                _lastPageInfo = now
                DispatchQueue.main.async { info(now.0, now.1) }
            }
        }
        if let report = _w.onCaretRect {
            if focused, let c = caretRect {
                report(Rect.fromLTWH(c.left + _originX, c.top + pad.top - _scrollY, c.width, c.height))
            } else {
                report(nil)
            }
        }
    }

    // MARK: Build

    public override func build(_ context: any BuildContext) -> Widget {
        // An I-beam everywhere in the editor, as Word shows over the page —
        // except an arrow over a selected picture and resize cursors on
        // its handles.
        let cursor: MouseCursor
        if _textDrag?.active == true { cursor = _chords.alt ? SystemMouseCursors.copy : SystemMouseCursors.grabbing }
        else if let k = _hoverHandle ?? _handleDrag?.handle { cursor = Self._cursor(forHandle: k) }
        else if _hoverColumnBorder || _columnDrag != nil { cursor = SystemMouseCursors.resizeColumn }
        else if _hoverRowBorder || _rowDrag != nil { cursor = SystemMouseCursors.resizeRow }
        else if _hoverOverImage { cursor = SystemMouseCursors.basic }
        else if _hoverLink != nil && _chords.primary { cursor = SystemMouseCursors.click }
        else { cursor = SystemMouseCursors.text }
        return MouseRegion(onExit: { [weak self] _ in
            guard let self, self._hoverLink != nil || self._hoverHandle != nil || self._hoverOverImage || self._hoverColumnBorder || self._hoverRowBorder else { return }
            self._hoverLink = nil
            self._w.onLinkHover?(nil)
            self.setState { self._hoverHandle = nil; self._hoverOverImage = false; self._hoverColumnBorder = false; self._hoverRowBorder = false }
        }, cursor: cursor, child: Listener(
            onPointerDown: { [weak self] e in self?._pointerDown(e) },
            onPointerMove: { [weak self] e in self?._pointerMove(e) },
            onPointerUp: { [weak self] e in self?._pointerUp(e) },
            onPointerHover: { [weak self] e in self?._pointerHover(e) },
            onPointerCancel: { [weak self] e in self?._pointerCancel(e) },
            onPointerPanZoomStart: { [weak self] e in self?._panZoomStart(e) },
            onPointerPanZoomUpdate: { [weak self] e in self?._panZoomUpdate(e) },
            onPointerPanZoomEnd: { [weak self] e in self?._panZoomEnd(e) },
            onPointerSignal: { [weak self] e in self?._pointerSignal(e) },
            behavior: .opaque,
            child: CustomPaint(painter: _painter, child: SizedBox(expand: ()))
        ))
    }
}

private final class _RichEditablePainter: CustomPainter {
    unowned let state: RichEditableState

    init(state: RichEditableState, repaint: any Listenable) {
        self.state = state
        super.init(repaint: repaint)
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        state._paint(canvas, size)
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        return true
    }
}
