// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

// MARK: - Theme (macOS TextEdit look: flat toolbar over a paper-white page)

private struct EditorPalette {
    let background: Color      // window chrome behind the page
    let page: Color            // the document surface
    let toolbar: Color
    let toolbarLine: Color
    let text: Color
    let dimText: Color
    let caret: Color
    let control: Color         // idle control fill
    let controlActive: Color   // toggled control fill
    let controlText: Color
    let accent: Color
    let selection: Color

    init(dark: Bool) {
        if dark {
            background = Color(0xA6262930)
            page = Color(0xFF1E1E20)
            toolbar = Color(0xB32E3138)
            toolbarLine = Color(0x33000000)
            text = Color(0xFFE8E8E8)
            dimText = Color(0x88FFFFFF)
            caret = Color(0xFF4FA8FF)
            control = Color(0x1FFFFFFF)
            controlActive = Color(0x4D0A84FF)
            controlText = Color(0xFFEEEEEE)
            accent = Color(0xFF0A84FF)
            selection = Color(0x590A84FF)
        } else {
            background = Color(0xCCECECEE)
            page = Color(0xFFFFFFFF)
            toolbar = Color(0xCCF3F3F5)
            toolbarLine = Color(0x22000000)
            text = Color(0xFF1D1D1F)
            dimText = Color(0x88000000)
            caret = Color(0xFF0068D0)
            control = Color(0x10000000)
            controlActive = Color(0x330A6BDF)
            controlText = Color(0xFF1D1D1F)
            accent = Color(0xFF007AFF)
            selection = Color(0x400A6BDF)
        }
    }
}

// MARK: - X11 keysyms (as delivered in KeyData.logical by the DRM embedder)

private enum Keysym {
    static let backspace: Int64 = 0xFF08
    static let tab: Int64 = 0xFF09
    static let enter: Int64 = 0xFF0D
    static let home: Int64 = 0xFF50
    static let left: Int64 = 0xFF51
    static let up: Int64 = 0xFF52
    static let right: Int64 = 0xFF53
    static let down: Int64 = 0xFF54
    static let pageUp: Int64 = 0xFF55
    static let pageDown: Int64 = 0xFF56
    static let end: Int64 = 0xFF57
    static let kpEnter: Int64 = 0xFF8D
    static let shiftL: Int64 = 0xFFE1
    static let shiftR: Int64 = 0xFFE2
    static let ctrlL: Int64 = 0xFFE3
    static let ctrlR: Int64 = 0xFFE4
    static let altL: Int64 = 0xFFE9
    static let altR: Int64 = 0xFFEA
    static let delete: Int64 = 0xFFFF
    static let escape: Int64 = 0xFF1B
}

// MARK: - Toolbar alignment glyphs

/// Four text lines whose lengths/positions read as left/center/right align.
private class AlignIconPainter: CustomPainter {
    let mode: ParagraphAttrs.Align
    let color: Color

    init(_ mode: ParagraphAttrs.Align, color: Color) {
        self.mode = mode
        self.color = color
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let paint = Paint()
        paint.color = color
        paint.style = .fill
        let widths: [Double] = [1.0, 0.65, 1.0, 0.65]
        let lineH = size.height / 9
        for (i, frac) in widths.enumerated() {
            let w = size.width * frac
            let x: Double
            switch mode {
            case .left: x = 0
            case .center: x = (size.width - w) / 2
            case .right: x = size.width - w
            }
            let y = Double(i) * size.height / 4 + lineH
            canvas.drawRRect(
                RRect(fromRectAndRadius: Rect.fromLTWH(x, y, w, lineH),
                      Radius(circular: lineH / 2)),
                paint)
        }
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? AlignIconPainter else { return true }
        return old.mode != mode || old.color != color
    }
}

// MARK: - Document painter

/// One laid-out paragraph: the painter plus its vertical slot.
private struct ParaLayout {
    let painter: TextPainter
    let y: Double
    let height: Double
}

/// Paints every visible paragraph plus the caret. Painting from the SAME
/// TextPainters used for hit-testing keeps caret/click math exact.
private class DocumentPainter: CustomPainter {
    let layouts: [ParaLayout]
    let originX: Double
    let originY: Double        // pad - scrollY
    let caret: Rect?           // in document coords (pre-origin)
    let caretColor: Color
    let selectionRects: [Rect] // document coords (pre-origin)
    let selectionColor: Color

    init(layouts: [ParaLayout], originX: Double, originY: Double,
         caret: Rect?, caretColor: Color,
         selectionRects: [Rect], selectionColor: Color) {
        self.layouts = layouts
        self.originX = originX
        self.originY = originY
        self.caret = caret
        self.caretColor = caretColor
        self.selectionRects = selectionRects
        self.selectionColor = selectionColor
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        if !selectionRects.isEmpty {
            let paint = Paint()
            paint.color = selectionColor
            paint.style = .fill
            for rect in selectionRects {
                canvas.drawRect(
                    Rect.fromLTWH(originX + rect.left, originY + rect.top,
                                  rect.width, rect.height),
                    paint)
            }
        }
        for layout in layouts {
            let top = originY + layout.y
            if top + layout.height < 0 || top > size.height { continue }
            layout.painter.paint(canvas, Offset(originX, top))
        }
        if let caret {
            let paint = Paint()
            paint.color = caretColor
            paint.style = .fill
            canvas.drawRRect(
                RRect(fromRectAndRadius:
                        Rect.fromLTWH(originX + caret.left, originY + caret.top,
                                      caret.width, caret.height),
                      Radius(circular: 1)),
                paint)
        }
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        // Layout objects are rebuilt per state change; repaint whenever a
        // new painter instance shows up (cheap — paints only visible rows).
        return true
    }
}

// MARK: - TextEditorApp

class TextEditorApp: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _TextEditorAppState()
    }
}

class _TextEditorAppState: State<StatefulWidget>, @unchecked Sendable {

    private var buffer = EditorBuffer()
    private var pal = EditorPalette(dark: true)
    private var _isDark = true

    private let editorFocus = FocusNode(debugLabel: "EditorPane")
    private let pathController = TextEditingController()

    /// Document scroll offset in pixels.
    private var scrollY: Double = 0
    /// True while a mouse drag is extending the selection.
    private var _dragSelecting = false
    /// Pixel x the caret "wants" during vertical movement through short
    /// visual lines (the wrapped-line analogue of the buffer's sticky col).
    private var _stickyX: Double? = nil
    private var _lastClickAt: Double = 0
    private var _lastClickPos = Offset.zero
    private var _clickStreak = 1
    private var shiftDown = false
    /// True while this pane is the reported IME caret anchor.
    private var _sentImeCaret = false
    private var ctrlDown = false
    private var altDown = false
    /// Transient toolbar message (e.g. "Saved", "Open failed").
    private var statusMessage = ""

    /// Document-wide font size (TextEdit's per-document size control).
    private var docFontSize: Double = 15

    // File picker (in-app open/save panel)
    private enum PickerMode { case open, save }
    private var _pickerMode: PickerMode? = nil
    private var _pickerInitialDir = NSHomeDirectory()
    private var _pickerSuggestedName = "untitled.rtf"

    private let toolbarHeight: Double = 46
    private let pagePad: Double = 22       // padding inside the page
    private let pageMargin: Double = 18    // chrome around the page

    override func initState() {
        super.initState()

        editorFocus.onKeyData = { [weak self] keyData in
            return self?._handleKey(keyData) ?? false
        }
        editorFocus.onFocusChange = { [weak self] _ in
            self?.setState {}
        }
        editorFocus.requestFocus()

        // `TextEditorApp <path>` opens the file at startup.
        let args = CommandLine.arguments
        if args.count > 1 && !args[1].hasPrefix("-") {
            pathController.text = args[1]
            _openFile(args[1])
        }
    }

    override func dispose() {
        editorFocus.dispose()
        pathController.dispose()
        super.dispose()
    }

    // MARK: - Geometry

    private func _viewLogicalSize() -> Size {
        if let view = PlatformDispatcher.instance.implicitView {
            let dpr = view.devicePixelRatio
            let phys = view.physicalSize
            if phys.width > 0 && phys.height > 0 && dpr > 0 {
                return Size(phys.width / dpr, phys.height / dpr)
            }
        }
        return Size(920, 600)
    }

    private func _pageWidth() -> Double {
        _viewLogicalSize().width - pageMargin * 2
    }

    private func _wrapWidth() -> Double {
        max(80, _pageWidth() - pagePad * 2)
    }

    private func _viewportHeight() -> Double {
        max(0, _viewLogicalSize().height - toolbarHeight)
    }

    private func _style(for attrs: ParagraphAttrs) -> Flutter.TextStyle {
        Flutter.TextStyle(
            color: pal.text,
            fontSize: docFontSize,
            fontWeight: attrs.bold ? .w700 : .w400,
            fontStyle: attrs.italic ? .italic : .normal,
            decoration: attrs.underline ? .underline : nil,
            decorationColor: attrs.underline ? pal.text : nil
        )
    }

    private static func _textAlign(_ align: ParagraphAttrs.Align) -> TextAlign {
        switch align {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }

    /// Lay out every paragraph at the current wrap width. Rebuilt per state
    /// change — TextEdit-scale documents lay out in well under a frame.
    private func _layoutDocument() -> [ParaLayout] {
        let width = _wrapWidth()
        var result: [ParaLayout] = []
        result.reserveCapacity(buffer.lineCount)
        var y = 0.0
        for row in 0 ..< buffer.lineCount {
            let text = buffer.lines[row]
            let attrs = buffer.attrs[row]
            let painter = TextPainter(
                text: TextSpan(text: text.isEmpty ? " " : text,
                               style: _style(for: attrs)),
                textAlign: Self._textAlign(attrs.align),
                textDirection: .ltr
            )
            painter.layout(minWidth: width, maxWidth: width)
            let height = painter.height
            result.append(ParaLayout(painter: painter, y: y, height: height))
            y += height
        }
        return result
    }

    private func _documentHeight(_ layouts: [ParaLayout]) -> Double {
        guard let last = layouts.last else { return 0 }
        return last.y + last.height
    }

    /// UTF-16 offset for a Character-index column (TextPainter positions are
    /// engine UTF-16 offsets; emoji occupy two units).
    private static func _utf16Offset(_ line: String, col: Int) -> Int {
        String(line.prefix(col)).utf16.count
    }

    private static func _col(fromUtf16 offset: Int, in line: String) -> Int {
        var units = 0
        for (i, ch) in line.enumerated() {
            let w = String(ch).utf16.count
            if units + w > offset { return i }
            units += w
            if units >= offset { return i + 1 }
        }
        return line.count
    }

    /// Caret rect in document coordinates (pre-scroll, page-content space).
    private func _caretRect(_ layouts: [ParaLayout]) -> Rect {
        _rect(forRow: buffer.caretRow, col: buffer.caretCol, layouts: layouts)
    }

    private func _rect(forRow row: Int, col: Int, layouts: [ParaLayout]) -> Rect {
        guard row < layouts.count else {
            return Rect.fromLTWH(0, 0, 2, docFontSize * 1.3)
        }
        let layout = layouts[row]
        let line = buffer.lines[row]
        let lineH = layout.painter.preferredLineHeight
        let proto = Rect.fromLTWH(0, 0, 2, lineH)
        let offset = layout.painter.getOffsetForCaret(
            TextPosition(offset: Self._utf16Offset(line, col: col)),
            proto)
        return Rect.fromLTWH(offset.dx, layout.y + offset.dy, 2, lineH)
    }

    private func _ensureCaretVisible() {
        let layouts = _layoutDocument()
        let caret = _caretRect(layouts)
        let viewH = _viewportHeight() - pageMargin
        let docH = _documentHeight(layouts) + pagePad * 2
        let caretTop = caret.top + pagePad
        let caretBottom = caretTop + caret.height
        if caretTop < scrollY {
            scrollY = max(0, caretTop - 8)
        } else if caretBottom > scrollY + viewH {
            scrollY = caretBottom - viewH + 8
        }
        scrollY = max(0, min(scrollY, max(0, docH - viewH)))
    }

    // MARK: - Key handling

    private func _handleKey(_ keyData: KeyData) -> Bool {
        if keyData.logical == Keysym.ctrlL || keyData.logical == Keysym.ctrlR {
            ctrlDown = (keyData.type == .down || keyData.type == .repeat)
            return false
        }
        if keyData.logical == Keysym.shiftL || keyData.logical == Keysym.shiftR {
            shiftDown = (keyData.type == .down || keyData.type == .repeat)
            return false
        }
        if keyData.logical == Keysym.altL || keyData.logical == Keysym.altR {
            altDown = (keyData.type == .down || keyData.type == .repeat)
            return false
        }
        guard keyData.type == .down || keyData.type == .repeat else { return false }

        // Modal picker: Esc closes; everything else must not leak into the
        // document while it is up.
        if _pickerMode != nil {
            if keyData.logical == Keysym.escape {
                setState { _pickerMode = nil }
            }
            return true
        }

        var handled = true
        let isMovement: Bool
        switch keyData.logical {
        case Keysym.left, Keysym.right, Keysym.up, Keysym.down,
             Keysym.home, Keysym.end, Keysym.pageUp, Keysym.pageDown:
            isMovement = true
        default:
            isMovement = false
        }
        // Shift+movement extends the selection; plain movement collapses it.
        if isMovement {
            if shiftDown {
                buffer.beginSelection()
            } else {
                buffer.clearSelection()
            }
        }

        switch keyData.logical {
        case Keysym.enter, Keysym.kpEnter:
            buffer.insertNewline()
        case Keysym.backspace:
            if ctrlDown || altDown { buffer.deleteWordBack() } else { buffer.backspace() }
        case Keysym.delete:
            buffer.deleteForward()
        case Keysym.tab:
            buffer.insert("    ")
        case Keysym.left:
            if ctrlDown || altDown { buffer.moveWordLeft() } else { buffer.moveLeft() }
        case Keysym.right:
            if ctrlDown || altDown { buffer.moveWordRight() } else { buffer.moveRight() }
        case Keysym.up:
            _moveVisual(-1)
        case Keysym.down:
            _moveVisual(1)
        case Keysym.home:
            _moveLineEdge(home: true)
        case Keysym.end:
            _moveLineEdge(home: false)
        case Keysym.pageUp:
            _moveVisual(-1, pixels: (_viewportHeight() - pageMargin) * 0.9)
        case Keysym.pageDown:
            _moveVisual(1, pixels: (_viewportHeight() - pageMargin) * 0.9)
        default:
            handled = false
        }

        if !handled, let character = keyData.character, !character.isEmpty,
           let scalar = character.unicodeScalars.first {
            // Ctrl chords arrive as 0x00-0x1F control characters.
            if scalar.value == 0x13 || (ctrlDown && (character == "s" || character == "S")) {
                if shiftDown { _openPicker(.save) } else { _saveFile() }
                handled = true                                // Ctrl(+Shift)+S
            } else if scalar.value == 0x0F || (ctrlDown && (character == "o" || character == "O")) {
                _openPicker(.open)                            // Ctrl+O
                handled = true
            } else if scalar.value == 0x02 || (ctrlDown && (character == "b" || character == "B")) {
                setState { buffer.toggleBold() }              // Ctrl+B
                handled = true
            } else if scalar.value == 0x15 || (ctrlDown && (character == "u" || character == "U")) {
                setState { buffer.toggleUnderline() }         // Ctrl+U
                handled = true
            } else if scalar.value == 0x01 || (ctrlDown && (character == "a" || character == "A")) {
                buffer.selectAll()                            // Ctrl+A
                handled = true
            } else if scalar.value == 0x03 || (ctrlDown && (character == "c" || character == "C")) {
                _copySelection()                              // Ctrl+C
                handled = true
            } else if scalar.value == 0x18 || (ctrlDown && (character == "x" || character == "X")) {
                _copySelection()                              // Ctrl+X
                buffer.deleteSelection()
                handled = true
            } else if scalar.value == 0x16 || (ctrlDown && (character == "v" || character == "V")) {
                _paste()                                      // Ctrl+V
                handled = true
            } else if scalar.value >= 0x20 && scalar.value != 0x7F && !ctrlDown {
                buffer.insert(character)
                handled = true
            }
        }

        guard handled else { return false }
        switch keyData.logical {
        case Keysym.up, Keysym.down, Keysym.pageUp, Keysym.pageDown:
            break
        default:
            _stickyX = nil
        }
        _ensureCaretVisible()
        setState {}
        return true
    }

    /// Document position nearest a point in document coordinates.
    private func _position(atDocX x: Double, docY y: Double,
                           layouts: [ParaLayout]) -> (row: Int, col: Int) {
        var row = layouts.count - 1
        for (i, layout) in layouts.enumerated() where y < layout.y + layout.height {
            row = i
            break
        }
        let layout = layouts[row]
        let position = layout.painter.getPositionForOffset(
            Offset(x, max(0, y - layout.y)))
        return (row, Self._col(fromUtf16: position.offset, in: buffer.lines[row]))
    }

    /// Move the caret one visual line (or `pixels`) up/down, staying in the
    /// same pixel column across wrapped lines and paragraph boundaries.
    private func _moveVisual(_ direction: Int, pixels: Double? = nil) {
        let layouts = _layoutDocument()
        guard !layouts.isEmpty else { return }
        let caret = _caretRect(layouts)
        let x = _stickyX ?? caret.left
        _stickyX = x
        let step = pixels ?? caret.height
        let targetY = caret.top + caret.height / 2 + Double(direction) * step
        if targetY < 0 {
            buffer.moveTo(row: 0, col: 0, selecting: shiftDown)
        } else if targetY > _documentHeight(layouts) {
            let lastRow = buffer.lineCount - 1
            buffer.moveTo(row: lastRow, col: buffer.lines[lastRow].count,
                          selecting: shiftDown)
        } else {
            let pos = _position(atDocX: x, docY: targetY, layouts: layouts)
            buffer.moveTo(row: pos.row, col: pos.col, selecting: shiftDown)
        }
    }

    /// Home/End within the caret's VISUAL line (wrapped-line aware).
    private func _moveLineEdge(home: Bool) {
        let layouts = _layoutDocument()
        guard !layouts.isEmpty else { return }
        let caret = _caretRect(layouts)
        let y = caret.top + caret.height / 2
        let x = home ? 0.0 : _wrapWidth() + 1000
        var pos = _position(atDocX: x, docY: y, layouts: layouts)
        if !home, pos.col > 0 {
            // A soft-wrap boundary offset renders at the NEXT visual line's
            // start; step back so End stays on the caret's line.
            let rendered = _rect(forRow: pos.row, col: pos.col, layouts: layouts)
            if rendered.top > caret.top + caret.height / 2 {
                pos.col -= 1
            }
        }
        buffer.moveTo(row: pos.row, col: pos.col, selecting: shiftDown)
    }

    // MARK: - Clipboard (the system selection, shared with every application)

    private func _copySelection() {
        guard let text = buffer.selectedText else { return }
        Clipboard.setData(ClipboardData(text: text))
    }

    private func _paste() {
        // Asynchronous by nature: the current owner may be another process
        // that has to be asked to write. The completion lands on the UI thread.
        // The key handler's own setState has already run by the time this
        // lands, so the insert has to drive its own rebuild.
        Clipboard.getData(Clipboard.kTextPlain) { [weak self] data in
            guard let self = self,
                  let text = data?.text, !text.isEmpty else { return }
            self._insertMultiline(text)
            self._ensureCaretVisible()
            self.setState {}
        }
    }

    /// Insert text that may span lines (buffer.insert is single-line).
    private func _insertMultiline(_ text: String) {
        let parts = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        for (i, part) in parts.enumerated() {
            if i > 0 { buffer.insertNewline() }
            if !part.isEmpty { buffer.insert(part) }
        }
    }

    // MARK: - File operations

    private func _openFile(_ path: String) {
        let expanded = NSString(string: path).expandingTildeInPath
        do {
            let content = try String(contentsOfFile: expanded, encoding: .utf8)
            if let doc = EditorRtf.parse(content) {
                buffer.loadRich(lines: doc.lines, attrs: doc.attrs)
                if let size = doc.fontSize {
                    docFontSize = min(48, max(9, size))
                }
            } else {
                buffer.load(content)
            }
            scrollY = 0
            statusMessage = ""
        } catch {
            statusMessage = "Open failed: \(error.localizedDescription)"
        }
        setState {}
    }

    private func _saveFile() {
        let path = pathController.text.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else {
            setState { statusMessage = "Enter a file path to save" }
            return
        }
        let expanded = NSString(string: path).expandingTildeInPath
        let asRtf = expanded.lowercased().hasSuffix(".rtf")
        do {
            let payload = asRtf
                ? EditorRtf.serialize(lines: buffer.lines, attrs: buffer.attrs,
                                      fontSize: docFontSize)
                : buffer.text
            try payload.write(toFile: expanded, atomically: true, encoding: .utf8)
            buffer.markSaved()
            statusMessage = !asRtf && buffer.hasFormatting
                ? "Saved as plain text — use .rtf to keep formatting"
                : "Saved"
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
        setState {}
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        _isDark = theme.brightness == .dark
        pal = EditorPalette(dark: _isDark)

        var layers: [Widget] = [
            ColoredBox(
                color: pal.background,
                child: Column(children: [
                    _formatBar(),
                    Expanded(child: _documentView()),
                ])
            )
        ]
        if _pickerMode != nil {
            layers.append(_pickerOverlay())
        }
        return Stack(children: layers)
    }

    // MARK: - Format bar (TextEdit style)

    private func _formatBar() -> Widget {
        let attrs = buffer.caretAttrs
        return SizedBox(
            height: toolbarHeight,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: pal.toolbar,
                    border: Border(bottom: BorderSide(color: pal.toolbarLine, width: 1))
                ),
                child: Padding(
                    padding: EdgeInsets(horizontal: 10, vertical: 8),
                    child: Row(children: [
                        _faceToggle("B", active: attrs.bold, weight: .w700,
                                    italic: false) { [self] in
                            setState { buffer.toggleBold() }
                        },
                        SizedBox(width: 4),
                        _faceToggle("I", active: attrs.italic, weight: .w500,
                                    italic: true) { [self] in
                            setState { buffer.toggleItalic() }
                        },
                        SizedBox(width: 4),
                        _faceToggle("U", active: attrs.underline, weight: .w500,
                                    italic: false, underline: true) { [self] in
                            setState { buffer.toggleUnderline() }
                        },
                        SizedBox(width: 12),
                        _alignButton(.left, current: attrs.align),
                        SizedBox(width: 3),
                        _alignButton(.center, current: attrs.align),
                        SizedBox(width: 3),
                        _alignButton(.right, current: attrs.align),
                        SizedBox(width: 12),
                        _sizeButton("−") { [self] in
                            setState { docFontSize = max(9, docFontSize - 1) }
                        },
                        SizedBox(width: 5),
                        Text("\(Int(docFontSize))", style: TextStyle(
                            color: pal.controlText, fontSize: 13)),
                        SizedBox(width: 5),
                        _sizeButton("+") { [self] in
                            setState { docFontSize = min(48, docFontSize + 1) }
                        },
                        SizedBox(width: 14),
                        Expanded(
                            child: FluentTextBox(
                                controller: pathController,
                                placeholderText: "~/untitled.rtf",
                                onSubmitted: { [self] path in
                                    _openFile(path)
                                }
                            )
                        ),
                        SizedBox(width: 8),
                        _barButton("Open") { [self] in
                            _openPicker(.open)
                        },
                        SizedBox(width: 6),
                        _barButton(buffer.modified ? "Save •" : "Save") { [self] in
                            let path = pathController.text
                                .trimmingCharacters(in: .whitespaces)
                            if path.isEmpty { _openPicker(.save) } else { _saveFile() }
                        },
                        _statusLabel(),
                    ])
                )
            )
        )
    }

    private func _statusLabel() -> Widget {
        guard !statusMessage.isEmpty else { return SizedBox(width: 0, height: 0) }
        return Padding(
            padding: EdgeInsets(left: 8, top: 0, right: 0, bottom: 0),
            child: Text(statusMessage, style: TextStyle(
                color: pal.dimText, fontSize: 11), maxLines: 1)
        )
    }

    private func _faceToggle(_ label: String, active: Bool, weight: FontWeight,
                             italic: Bool, underline: Bool = false,
                             onTap: @escaping () -> Void) -> Widget {
        return GestureDetector(
            onTap: onTap,
            behavior: .opaque,
            child: SizedBox(width: 30, height: 28, child: DecoratedBox(
                decoration: BoxDecoration(
                    color: active ? pal.controlActive : pal.control,
                    borderRadius: BorderRadius.all(Radius(circular: 6))
                ),
                child: Center(child: Text(label, style: TextStyle(
                    color: active ? pal.accent : pal.controlText,
                    fontSize: 14,
                    fontWeight: weight,
                    fontStyle: italic ? .italic : .normal,
                    decoration: underline ? .underline : nil,
                    decorationColor: underline
                        ? (active ? pal.accent : pal.controlText) : nil
                )))
            ))
        )
    }

    private func _alignButton(_ mode: ParagraphAttrs.Align,
                              current: ParagraphAttrs.Align) -> Widget {
        let active = mode == current
        return GestureDetector(
            onTap: { [self] in
                setState { buffer.setCaretAlign(mode) }
            },
            behavior: .opaque,
            child: SizedBox(width: 30, height: 28, child: DecoratedBox(
                decoration: BoxDecoration(
                    color: active ? pal.controlActive : pal.control,
                    borderRadius: BorderRadius.all(Radius(circular: 6))
                ),
                child: Center(child: SizedBox(width: 14, height: 12,
                    child: CustomPaint(painter: AlignIconPainter(
                        mode, color: active ? pal.accent : pal.controlText))))
            ))
        )
    }

    private func _sizeButton(_ label: String, onTap: @escaping () -> Void) -> Widget {
        return GestureDetector(
            onTap: onTap,
            behavior: .opaque,
            child: SizedBox(width: 26, height: 28, child: DecoratedBox(
                decoration: BoxDecoration(
                    color: pal.control,
                    borderRadius: BorderRadius.all(Radius(circular: 6))
                ),
                child: Center(child: Text(label, style: TextStyle(
                    color: pal.controlText, fontSize: 15)))
            ))
        )
    }

    private func _barButton(_ label: String, onTap: @escaping () -> Void) -> Widget {
        return GestureDetector(
            onTap: onTap,
            behavior: .opaque,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: pal.control,
                    borderRadius: BorderRadius.all(Radius(circular: 6))
                ),
                child: Padding(
                    padding: EdgeInsets(horizontal: 13, vertical: 6),
                    child: Text(label, style: TextStyle(
                        color: pal.controlText, fontSize: 13))
                )
            )
        )
    }

    // MARK: - File picker (the shared Fluent file dialog)

    private func _openPicker(_ mode: PickerMode) {
        let current = NSString(string: pathController.text
            .trimmingCharacters(in: .whitespaces)).expandingTildeInPath
        var dir = (current as NSString).deletingLastPathComponent
        var isDirObj: ObjCBool = false
        if current.isEmpty
            || !FileManager.default.fileExists(atPath: dir, isDirectory: &isDirObj)
            || !isDirObj.boolValue {
            dir = NSHomeDirectory()
        }
        let base = (current as NSString).lastPathComponent
        setState {
            _pickerInitialDir = dir
            _pickerSuggestedName = base.isEmpty ? "untitled.rtf" : base
            _pickerMode = mode
        }
    }

    private func _pickerOverlay() -> Widget {
        let mode = _pickerMode ?? .open
        var opts = FluentFilePanelOptions()
        opts.mode = mode == .open ? .open : .save
        opts.appearanceDark = _isDark
        opts.initialDirectory = _pickerInitialDir
        if mode == .save { opts.suggestedName = _pickerSuggestedName }
        return FluentFilePanelOverlay(options: opts) { [self] paths in
            setState { _pickerMode = nil }
            guard let path = paths.first else { return }
            pathController.text = path
            if mode == .open {
                _openFile(path)
            } else {
                _saveFile()
            }
        }
    }

    // MARK: - Document view

    private func _documentView() -> Widget {
        let layouts = _layoutDocument()
        let caret = editorFocus.hasFocus ? _caretRect(layouts) : nil

        #if os(Linux)
        // Report the caret to the shell (IME candidate panel anchor) —
        // content coordinates. One-shot clear on focus loss.
        if editorFocus.hasFocus {
            let rect = caret ?? _caretRect(layouts)
            let x = pageMargin + pagePad + rect.left
            let y = toolbarHeight + pagePad + rect.top - scrollY
            let visible = y >= toolbarHeight - rect.height
                && y <= _viewLogicalSize().height
            GpuDmaBufRenderer.current?.sendCaret(
                owner: self, x: x, y: y, width: 2, height: rect.height,
                visible: visible)
            _sentImeCaret = true
        } else if _sentImeCaret {
            _sentImeCaret = false
            GpuDmaBufRenderer.current?.sendCaret(
                owner: self, x: 0, y: 0, width: 0, height: 0, visible: false)
        }
        #endif

        let painter = DocumentPainter(
            layouts: layouts,
            originX: pagePad,
            originY: pagePad - scrollY,
            caret: caret,
            caretColor: pal.caret,
            selectionRects: _selectionRects(layouts),
            selectionColor: pal.selection
        )

        // The page floats on the chrome background with a soft shadow,
        // TextEdit-style; text paints inside it via DocumentPainter.
        return Listener(
            onPointerDown: { [self] event in
                editorFocus.requestFocus()
                guard event.buttons & 1 != 0 else { return }
                let x = event.localPosition.dx - pageMargin - pagePad
                let y = event.localPosition.dy + scrollY - pagePad
                let now = Date().timeIntervalSince1970
                let near = abs(event.localPosition.dx - _lastClickPos.dx) < 6
                    && abs(event.localPosition.dy - _lastClickPos.dy) < 6
                _clickStreak = (now - _lastClickAt < 0.45 && near) ? _clickStreak + 1 : 1
                _lastClickAt = now
                _lastClickPos = event.localPosition
                _dragSelecting = true
                _moveCaret(toDocX: x, docY: y, layouts: layouts,
                           selecting: shiftDown)
                if _clickStreak == 2 {
                    _dragSelecting = false
                    setState { buffer.selectWord() }
                } else if _clickStreak >= 3 {
                    _dragSelecting = false
                    setState { buffer.selectParagraph() }
                }
            },
            onPointerMove: { [self] event in
                guard _dragSelecting, event.buttons & 1 != 0 else { return }
                let x = event.localPosition.dx - pageMargin - pagePad
                let y = event.localPosition.dy + scrollY - pagePad
                _moveCaret(toDocX: x, docY: y, layouts: _layoutDocument(),
                           selecting: true)
            },
            onPointerUp: { [self] _ in
                _dragSelecting = false
            },
            onPointerSignal: { [self] event in
                guard let scroll = event as? PointerScrollEvent else { return }
                let viewH = _viewportHeight() - pageMargin
                let docH = _documentHeight(layouts) + pagePad * 2
                let target = max(0, min(scrollY + scroll.scrollDelta.dy,
                                        max(0, docH - viewH)))
                if target != scrollY {
                    setState { scrollY = target }
                }
            },
            behavior: .opaque,
            child: Padding(
                padding: EdgeInsets(left: pageMargin, top: 0,
                                    right: pageMargin, bottom: pageMargin),
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: pal.page,
                        borderRadius: BorderRadius.all(Radius(circular: 6)),
                        boxShadow: [BoxShadow(color: Color(0x30000000),
                                              offset: Offset(0, 2),
                                              blurRadius: 10)]
                    ),
                    child: ClipRRect(
                        borderRadius: BorderRadius.all(Radius(circular: 6)),
                        child: CustomPaint(
                            painter: painter,
                            child: SizedBox(expand: ())
                        )
                    )
                )
            )
        )
    }

    private func _moveCaret(toDocX x: Double, docY y: Double,
                            layouts: [ParaLayout], selecting: Bool = false) {
        guard !layouts.isEmpty else { return }
        let pos = _position(atDocX: x, docY: y, layouts: layouts)
        _stickyX = nil
        setState {
            buffer.moveTo(row: pos.row, col: pos.col, selecting: selecting)
            statusMessage = ""
        }
    }

    /// Highlight rects for the current selection, in document coordinates.
    private func _selectionRects(_ layouts: [ParaLayout]) -> [Rect] {
        guard let range = buffer.selectionRange else { return [] }
        let (start, end) = (range.start, range.end)
        var rects: [Rect] = []
        for row in start.row ... end.row {
            guard row < layouts.count else { break }
            let layout = layouts[row]
            let line = buffer.lines[row]
            let fromCol = row == start.row ? start.col : 0
            let toCol = row == end.row ? end.col : line.count
            let fromOff = Self._utf16Offset(line, col: fromCol)
            let toOff = Self._utf16Offset(line, col: toCol)
            if fromOff == toOff {
                // Empty span (blank line inside the selection): a slim stub
                // so the row still reads as selected.
                rects.append(Rect.fromLTWH(0, layout.y, 7,
                                           layout.painter.preferredLineHeight))
                continue
            }
            let boxes = layout.painter.getBoxesForSelection(
                TextSelection(baseOffset: fromOff, extentOffset: toOff))
            for box in boxes {
                let rect = box.toRect()
                rects.append(Rect.fromLTWH(rect.left, layout.y + rect.top,
                                           rect.width, rect.height))
            }
        }
        return rects
    }
}
