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
    /// The link under the pointer, or nil as it leaves one — for a status bar.
    public let onLinkHover: ((String?) -> Void)?
    /// ⌘-click on a link. Nil opens it through the host.
    public let onLinkActivate: ((String) -> Void)?
    /// A pointer selection gesture ended (drag, double or triple click)
    /// with a non-empty selection — when Word's Format Painter applies.
    public let onSelectionGestureEnd: (() -> Void)?
    /// Checks paragraphs as they are shown and underlines misspellings.
    public let spellChecker: RichSpellChecker?
    /// A right click, with the pointer's position in global coordinates.
    /// The caret has moved there unless the click was inside the selection.
    public let onContextMenu: ((Offset) -> Void)?

    public init(key: (any Key)? = nil, controller: RichDocumentController,
                theme: RichTextTheme = RichTextTheme(),
                padding: EdgeInsets = EdgeInsets(left: 24, top: 24, right: 24, bottom: 24),
                focusNode: FocusNode? = nil, autofocus: Bool = true,
                backgroundColor: Color? = nil, zoom: Double = 1.0,
                pageSetup: PageSetup? = nil, pageColor: Color = Color(0xFFFFFFFF),
                onCaretRect: ((Rect?) -> Void)? = nil,
                onPageInfo: ((Int, Int) -> Void)? = nil,
                onShortcut: ((KeyData, KeyModifiers) -> Bool)? = nil,
                onLinkHover: ((String?) -> Void)? = nil,
                onLinkActivate: ((String) -> Void)? = nil,
                onSelectionGestureEnd: (() -> Void)? = nil,
                onContextMenu: ((Offset) -> Void)? = nil,
                spellChecker: RichSpellChecker? = nil) {
        self.controller = controller
        self.theme = theme
        self.padding = padding
        self.focusNode = focusNode
        self.autofocus = autofocus
        self.backgroundColor = backgroundColor
        self.zoom = zoom
        self.pageSetup = pageSetup
        self.pageColor = pageColor
        self.onCaretRect = onCaretRect
        self.onPageInfo = onPageInfo
        self.onShortcut = onShortcut
        self.onLinkHover = onLinkHover
        self.onLinkActivate = onLinkActivate
        self.onSelectionGestureEnd = onSelectionGestureEnd
        self.onContextMenu = onContextMenu
        self.spellChecker = spellChecker
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return RichEditableState()
    }
}

public final class RichEditableState: State<StatefulWidget> {
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
    /// A picture-handle drag: which handle (0–7, clockwise from top-left),
    /// where it started, the picture's size then, and the live size.
    private var _handleDrag: (index: Int, handle: Int, start: Offset, size: Size)? = nil
    private var _dragSize: Size? = nil
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
    /// A press inside the selection: a drag of the selected text once the
    /// pointer moves, a click that collapses the selection if it does not.
    private var _textDrag: (start: Offset, active: Bool)? = nil
    /// Where the dragged text would land, painted as a second caret.
    private var _dropPosition: RichPosition? = nil
    /// A spell-check pass is scheduled (one at a time, after an idle).
    private var _spellScheduled = false
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
        _ = s.withCString { write(2, $0, strlen($0)) }
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

    public var viewportSize: Size { _viewport }

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
        _focus.onKeyData = { [weak self] keyData in
            return self?._handleKey(keyData) ?? false
        }
        _focus.onFocusChange = { [weak self] focused in
            guard let self else { return }
            if !focused { self._chords.reset() }
            if focused { self._textInput?.attach() } else { self._textInput?.detach() }
            self._caretVisible = true
            self._restartBlink()
            self._repaint.notifyListeners()
        }
        _layout = RichLayout(theme: _w.theme, paragraphCount: _controller.document.paragraphs.count)
        _layout.scale = _w.zoom
        _layout.pageSetup = _w.pageSetup
        _layout.onNeedsRepaint = { [weak self] in self?._repaint.notifyListeners() }
        _layout.spellChecker = _w.spellChecker
        _painter = _RichEditablePainter(state: self, repaint: _repaint)
        _controller.addListener(_onControllerChanged)
        if RichTextInputConnection.enabled { _textInput = RichTextInputConnection(controller: _controller) }
        if _w.autofocus { _focus.requestFocus() }
        _restartBlink()
    }

    public override func didUpdateWidget(_ oldWidget: StatefulWidget) {
        super.didUpdateWidget(oldWidget)
        let old = oldWidget as! RichEditable
        if old.controller !== _w.controller {
            old.controller.removeListener(_onControllerChanged)
            _controller = _w.controller
            _controller.addListener(_onControllerChanged)
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
        _controller.removeListener(_onControllerChanged)
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
        let maxY = max(0, contentHeight - _viewport.height)
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
            _scrollY = max(0, top - margin)
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
        if _chords.track(keyData) {
            // A modifier alone: the pointer over a link changes shape with ⌘.
            if _hoverLink != nil || _textDrag?.active == true { setState {} }
            return false
        }
        guard keyData.type == .down || keyData.type == .repeat else { return false }
        let c = _controller!
        let shift = _chords.shift
        let key = KeyChordTracker.named(keyData.logical)
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
            if _chords.primary && KeyModifiers.primary == .meta { c.moveToDocumentStart(extend: shift) }
            else if _chords.alt { c.moveToParagraphStart(extend: shift) }
            else { _moveVertical(down: false, extend: shift) }
        case .down:
            keepStickyX = true
            if _chords.primary && KeyModifiers.primary == .meta { c.moveToDocumentEnd(extend: shift) }
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
            else if shift { c.indent(-1) } else if c.hasSelection { c.indent(1) } else { c.insertText("\t") }
        case .escape:
            if c.hasSelection { c.moveTo(c.caret, extend: false) } else { return false }
        default:
            if _chords.primary, !_chords.alt, let letter = KeyChordTracker.letter(keyData.logical) {
                switch letter {
                case "a": c.selectAll()
                case "c": _copy()
                case "x": _cut()
                case "v": if shift { _pastePlain() } else { _paste() }
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
                self._controller.insertText(text.replacingOccurrences(of: "\r\n", with: "\n"))
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
                self._controller.paste(text: text.replacingOccurrences(of: "\r\n", with: "\n"))
            }
        }
    }

    // MARK: Pointer

    private func _canvasPoint(_ local: Offset) -> Offset {
        Offset(local.dx - _originX, local.dy + _scrollY - _w.padding.top)
    }

    /// The selected picture's box in the editable's own coordinates, with
    /// the live drag size when one is under way.
    private func _selectedImageBox() -> (index: Int, rect: Rect)? {
        if _layout.width > 0 { _syncLayoutIfNeeded() }
        guard let i = _controller.selectedImageIndex, _layout.width > 0,
              let flow = _layout.imageRect(i), let canvas = _layout.canvasRects(flow).first else { return nil }
        var rect = Rect.fromLTWH(canvas.left + _originX, canvas.top + _w.padding.top - _scrollY,
                                 canvas.width, canvas.height)
        if let d = _dragSize { rect = Rect.fromLTWH(rect.left, rect.top, d.width, d.height) }
        return (i, rect)
    }

    /// Handle centres, clockwise from the top-left corner: 0 TL, 1 T, 2 TR,
    /// 3 R, 4 BR, 5 B, 6 BL, 7 L.
    private static func _handles(_ r: Rect) -> [Offset] {
        [Offset(r.left, r.top), Offset(r.center.dx, r.top), Offset(r.right, r.top), Offset(r.right, r.center.dy),
         Offset(r.right, r.bottom), Offset(r.center.dx, r.bottom), Offset(r.left, r.bottom), Offset(r.left, r.center.dy)]
    }

    private func _handleHit(_ p: Offset, _ rect: Rect) -> Int? {
        let reach = Self.handleSize
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
        let x = _canvasPoint(local).dx
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
        let link = handle == nil && !overImage && !border ? _link(at: event.localPosition) : nil
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
        let hadDrop = _dropPosition != nil || _columnDragWidths != nil || _dragSize != nil
        _dragging = false
        _unitDrag = nil
        _textDrag = nil
        _dropPosition = nil
        _handleDrag = nil
        _dragSize = nil
        if let drag = _columnDrag {
            _columnDrag = nil
            _columnDragWidths = nil
            _layout.previewColumns(drag.table, nil, _controller.document)
        }
        if hadDrop { _repaint.notifyListeners() }
    }

    private func _pointerDown(_ event: PointerEvent) {
        _textDrag = nil
        _dropPosition = nil
        if event.buttons & kSecondaryButton != 0 {
            _focus.requestFocus()
            if _layout.width > 0 {
                _syncLayoutIfNeeded()
                let pos = _layout.canvasPosition(at: _canvasPoint(event.localPosition), _controller.document)
                // Inside the selection the menu is about the selection;
                // elsewhere the caret goes to the click first, as Word does.
                if !_controller.hasSelection || pos < _controller.selection.start || pos > _controller.selection.end {
                    _controller.moveTo(pos, extend: false)
                }
            }
            // The event's position is already the view's: the menu goes there.
            _w.onContextMenu?(event.position)
            return
        }
        if _chords.primary, let link = _link(at: event.localPosition) {
            if let activate = _w.onLinkActivate { activate(link) } else { hostOpenURL?(link) }
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
        if let box = _selectedImageBox(), let k = _handleHit(event.localPosition, box.rect) {
            _handleDrag = (box.index, k, event.localPosition, box.rect.size)
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
        _focus.requestFocus()
        guard event.buttons & 1 != 0 else { return }
        _syncLayoutIfNeeded()
        guard _layout.width > 0 else { return }
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
               pos > sel.start, pos < sel.end, _controller.selectedImageIndex == nil {
                // Pressing on selected text starts a drag of it, not a new
                // selection; the caret moves only if the press stays put.
                _textDrag = (event.localPosition, false)
                _dragging = false
                return
            }
            _dragging = true
            _controller.moveTo(pos, extend: _chords.shift)
        case 2:
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
        if wasDragging, _controller.hasSelection { _w.onSelectionGestureEnd?() }
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
        if let drag = _handleDrag, let size = _dragSize {
            _handleDrag = nil
            _dragSize = nil
            let pt = _layout.theme.pixelsPerPoint * _layout.scale
            _controller.setImageSize(at: drag.index, width: size.width / pt, height: size.height / pt)
            _repaint.notifyListeners()
        }
    }

    private func _pointerSignal(_ event: PointerSignalEvent) {
        guard let scroll = event as? PointerScrollEvent else { return }
        let before = _scrollY
        _scrollY += scroll.scrollDelta.dy
        _clampScroll()
        if _scrollY != before { _repaint.notifyListeners() }
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
        _layout.paint(canvas, visible: visible, document: _controller.document,
                      selection: _controller.selection,
                      caret: (focused && _caretVisible && _controller.selection.isCollapsed) ? caretRect : nil,
                      pageBackground: { _, rect in
                          let shadow = Paint()
                          shadow.color = Color(0x22000000)
                          shadow.style = .fill
                          canvas.drawRect(rect.shift(Offset(0, 2)).inflate(1), shadow)
                          let paper = Paint()
                          paper.color = pageColor
                          paper.style = .fill
                          canvas.drawRect(rect, paper)
                      })
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

        // Scrollbar thumb.
        let total = contentHeight
        if total > size.height + 1 {
            let trackH = size.height - 4
            let thumbH = max(24, trackH * size.height / total)
            let thumbY = 2 + (trackH - thumbH) * (_scrollY / max(1, total - size.height))
            let paint = Paint()
            paint.color = Color(0x40808080)
            paint.style = .fill
            canvas.drawRRect(RRect(fromRectAndRadius: Rect.fromLTWH(size.width - 8, thumbY, 6, thumbH),
                                   Radius(circular: 3)), paint)
        }

        if let info = _w.onPageInfo {
            let now = (caretPage, pageCount)
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
        else if _hoverOverImage { cursor = SystemMouseCursors.basic }
        else if _hoverLink != nil && _chords.primary { cursor = SystemMouseCursors.click }
        else { cursor = SystemMouseCursors.text }
        return MouseRegion(onExit: { [weak self] _ in
            guard let self, self._hoverLink != nil || self._hoverHandle != nil || self._hoverOverImage || self._hoverColumnBorder else { return }
            self._hoverLink = nil
            self._w.onLinkHover?(nil)
            self.setState { self._hoverHandle = nil; self._hoverOverImage = false; self._hoverColumnBorder = false }
        }, cursor: cursor, child: Listener(
            onPointerDown: { [weak self] e in self?._pointerDown(e) },
            onPointerMove: { [weak self] e in self?._pointerMove(e) },
            onPointerUp: { [weak self] e in self?._pointerUp(e) },
            onPointerHover: { [weak self] e in self?._pointerHover(e) },
            onPointerCancel: { [weak self] e in self?._pointerCancel(e) },
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
