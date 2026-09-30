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

    public init(key: (any Key)? = nil, controller: RichDocumentController,
                theme: RichTextTheme = RichTextTheme(),
                padding: EdgeInsets = EdgeInsets(left: 24, top: 24, right: 24, bottom: 24),
                focusNode: FocusNode? = nil, autofocus: Bool = true,
                backgroundColor: Color? = nil, zoom: Double = 1.0,
                pageSetup: PageSetup? = nil, pageColor: Color = Color(0xFFFFFFFF),
                onCaretRect: ((Rect?) -> Void)? = nil,
                onPageInfo: ((Int, Int) -> Void)? = nil,
                onShortcut: ((KeyData, KeyModifiers) -> Bool)? = nil) {
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
            self._caretVisible = true
            self._restartBlink()
            self._repaint.notifyListeners()
        }
        _layout = RichLayout(theme: _w.theme, paragraphCount: _controller.document.paragraphs.count)
        _layout.scale = _w.zoom
        _layout.pageSetup = _w.pageSetup
        _layout.onNeedsRepaint = { [weak self] in self?._repaint.notifyListeners() }
        _painter = _RichEditablePainter(state: self, repaint: _repaint)
        _controller.addListener(_onControllerChanged)
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
        if _layout.pageSetup != _w.pageSetup { _layout.pageSetup = _w.pageSetup }
        _repaint.notifyListeners()
    }

    public override func dispose() {
        _blinkGeneration += 1
        _controller.removeListener(_onControllerChanged)
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
        if _chords.track(keyData) { return false }
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
            else { _moveVertical(down: false, extend: shift) }
        case .down:
            keepStickyX = true
            if _chords.primary && KeyModifiers.primary == .meta { c.moveToDocumentEnd(extend: shift) }
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
            if _chords.word { c.deleteWordBackward() } else { c.deleteBackward() }
        case .delete:
            if _chords.word { c.deleteWordForward() } else { c.deleteForward() }
        case .enter:
            c.insertParagraphBreak()
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
                case "v": _paste()
                case "z": if shift { c.redo() } else { c.undo() }
                case "y": c.redo()
                case "b": c.toggleBold()
                case "i": c.toggleItalic()
                case "u": c.toggleUnderline()
                default: return false
                }
            } else if let text = _chords.typedText(keyData) {
                c.insertText(text)
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

    // MARK: Clipboard

    private func _copy() {
        if let text = _controller.copySelection() {
            Clipboard.setData(ClipboardData(text: text))
        }
    }

    private func _cut() {
        if let text = _controller.cutSelection() {
            Clipboard.setData(ClipboardData(text: text))
        }
    }

    private func _paste() {
        Clipboard.getData(Clipboard.kTextPlain) { [weak self] data in
            guard let self, let text = data?.text, !text.isEmpty else { return }
            DispatchQueue.main.async {
                self._controller.paste(text: text.replacingOccurrences(of: "\r\n", with: "\n"))
            }
        }
    }

    // MARK: Pointer

    private func _canvasPoint(_ local: Offset) -> Offset {
        Offset(local.dx - _originX, local.dy + _scrollY - _w.padding.top)
    }

    private func _pointerDown(_ event: PointerEvent) {
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
            _dragging = true
            _controller.moveTo(pos, extend: _chords.shift)
        case 2:
            _dragging = false
            _controller.selectWord(at: pos)
        default:
            _dragging = false
            _controller.selectParagraph(at: pos)
        }
    }

    private func _pointerMove(_ event: PointerEvent) {
        guard _dragging, event.buttons & 1 != 0, _layout.width > 0 else { return }
        // Autoscroll when dragging past the edges.
        let y = event.localPosition.dy
        if y < 0 { _scrollY -= min(40, -y) } else if y > _viewport.height { _scrollY += min(40, y - _viewport.height) }
        _clampScroll()
        let pos = _layout.canvasPosition(at: _canvasPoint(event.localPosition), _controller.document)
        _controller.moveTo(pos, extend: true)
    }

    private func _pointerUp(_ event: PointerEvent) {
        _dragging = false
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
            contentWidth = max(1, setup.contentWidth * _layout.theme.pixelsPerPoint * _layout.scale)
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
        canvas.restore()

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
        return Listener(
            onPointerDown: { [weak self] e in self?._pointerDown(e) },
            onPointerMove: { [weak self] e in self?._pointerMove(e) },
            onPointerUp: { [weak self] e in self?._pointerUp(e) },
            onPointerSignal: { [weak self] e in self?._pointerSignal(e) },
            behavior: .opaque,
            child: CustomPaint(painter: _painter, child: SizedBox(expand: ()))
        )
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
