// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Slides window: title row and ribbon (shared with Writer), then the
// thumbnail pane, the slide canvas and the notes pane, then the status bar.
// Backstage is Writer's, with the deck's own New.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

final class SlidesShell: StatefulWidget {
    let initialPath: String?
    let onSwitch: (DocumentKind, String?) -> Void

    init(initialPath: String?, onSwitch: @escaping (DocumentKind, String?) -> Void) {
        self.initialPath = initialPath
        self.onSwitch = onSwitch
        super.init()
    }

    override func createState() -> State<StatefulWidget> { SlidesShellState() }
}

final class SlidesShellState: State<StatefulWidget> {
    let session = OfficeSession(kind: .presentation)
    private var deck: DeckController { session.deck! }
    private let _cache = SlideTextCache()
    /// The text the ribbon acts on when no body is being edited: nothing
    /// typed here ever shows.
    private let _scratch = RichDocumentController()
    private var _active: SlideShape? = nil
    private var _notesActive = false
    private var _focusShape: SlideShape? = nil
    private let _deckFocus = FocusNode(debugLabel: "slides deck")
    private let _deckChords = KeyChordTracker()
    private let _notesFocus = FocusNode(debugLabel: "slide notes")
    private let _notesTheme: RichTextTheme = {
        let t = RichTextTheme(fontFamily: "Calibri", fontSize: 12, headingColor: nil)
        t.fontFamilyResolver = OfficeFonts.substitute
        return t
    }()
    /// Last click was in the thumbnail pane: Delete then removes a slide.
    private var _paneFocused = false
    /// `deck.edits` when the deck was last opened or saved.
    private var _savedEdits = 0
    /// Shapes copied with ⌘C/⌘X while no text was being edited.
    private var _shapeClipboard: [ShapeState] = []
    /// Normal (canvas and notes) or Slide Sorter (a grid of every slide).
    private var _sorter = false
    /// The slide show, when running: the slide it started from.
    private var _show: Int? = nil
    /// A thumbnail being dragged to a new place: where it started, the
    /// pointer's start, and where it would land.
    private var _thumbDrag: (from: Int, startY: Double, startX: Double, to: Int, moved: Bool)? = nil
    private let _thumbMenu = FlyoutController()
    /// Double-click in the sorter, detected by hand: registering
    /// onDoubleTap kills taps on the DRM embedder (CLAUDE.md).
    private var _lastSorterTap: (index: Int, at: Date)? = nil
    private var _tab = RibbonTab.home
    private var _ribbonCollapsed = false
    private var _backstage: BackstagePage? = nil
    private var _status: String? = nil
    private var _statusGeneration = 0
    private var _showNotes = true
    private var _recent: [String] = []
    private let _search = TextEditingController()
    #if canImport(AppKit)
    private let _spelling: RichSpellChecker? = CocoaSpellChecker()
    #else
    private let _spelling: RichSpellChecker? = nil
    #endif

    private var _w: SlidesShell { widget as! SlidesShell }

    // MARK: Lifecycle

    override func initState() {
        super.initState()
        OfficeFonts.register()
        _recent = OfficeRecent.load()
        _wire()
        deck.addListener({ [weak self] in self?._deckChanged() }, owner: self)
        _cache.onImageDecoded = { [weak self] in
            guard let self, self.mounted else { return }
            self.setState {}
        }
        _point(at: nil)
        _deckFocus.onKeyData = { [weak self] key in self?._deckKey(key) ?? false }
        if let path = _w.initialPath { _open(path) }
        _deckFocus.requestFocus()
    }

    override func dispose() {
        deck.removeListeners(owner: self)
        session.controller.removeListeners(owner: self)
        _deckFocus.dispose()
        _notesFocus.dispose()
        _search.dispose()
        super.dispose()
    }

    private func _wire() {
        session.onBackstage = { [weak self] open in self?.setState { self?._backstage = open ? .home : nil } }
        session.onNew = { [weak self] in self?._newDeck() }
        session.onNewKind = { [weak self] kind in
            guard let self else { return }
            if kind == .presentation { self._newDeck() } else { self._w.onSwitch(.document, nil) }
        }
        session.onOpen = { [weak self] in self?.setState { self?._backstage = .open } }
        session.onSave = { [weak self] in self?._save() }
        session.onSaveAs = { [weak self] in self?.setState { self?._backstage = .saveAs } }
        session.onExport = { [weak self] ext in self?._export(ext) }
        session.onStatus = { [weak self] m in self?._flash(m) }
        session.onPaste = { [weak self] plain in
            guard let self else { return }
            let c = self.session.controller
            Clipboard.getData(plain ? Clipboard.kTextPlain : Clipboard.kAll) { data in
                guard let data, !data.isEmpty else { return }
                DispatchQueue.main.async {
                    if plain, let text = data.text {
                        c.insertText(text.replacingAll("\r\n", with: "\n"))
                    } else {
                        c.paste(data: data)
                    }
                }
            }
        }
        session.onInsertTextBox = { [weak self] in self?._insertTextBox() }
        session.onInsertShape = { [weak self] preset in
            guard let self else { return }
            self._endEditing()
            self.deck.addShape(preset)
            self._deckFocus.requestFocus()
        }
        session.onSlidesView = { [weak self] sorter in
            guard let self else { return }
            self._endEditing()
            self.setState { self._sorter = sorter }
        }
        session.onUndo = { [weak self] in self?._undo() }
        session.onRedo = { [weak self] in self?._redo() }
        session.onSlideShow = { [weak self] fromCurrent in
            guard let self else { return }
            self._startShow(at: fromCurrent ? self.deck.current : 0)
        }
        session.onToggleSpelling = { [weak self] in
            guard let self else { return }
            self.setState { self.session.checkSpelling.toggle() }
        }
    }

    // MARK: What the ribbon acts on

    /// Point the session (and so the ribbon, undo and the clipboard) at a
    /// text body, or at nothing.
    private func _point(at controller: RichDocumentController?, theme: RichTextTheme? = nil) {
        let next = controller ?? _scratch
        if next !== session.controller {
            session.controller.removeListeners(owner: self)
            session.controller = next
            next.addListener({ [weak self] in self?._textChanged() }, owner: self)
        }
        if let theme { session.theme = theme }
        session.summary = _summarize()
    }

    /// The ribbon's summary, with undo and redo covering the deck as well
    /// as the text being typed.
    private func _summarize() -> ToolbarSummary {
        var s = session.summarize()
        let typing = _active != nil || _notesActive
        s.canUndo = (typing && session.controller.canUndo) || deck.canUndo
        s.canRedo = (typing && session.controller.canRedo) || deck.canRedo
        s.revision = deck.revision
        return s
    }

    /// Start editing a shape's text, or stop editing (nil). Each editing
    /// session is one deck undo step once it ends.
    private func _activate(_ shape: SlideShape?) {
        _paneFocused = false
        if _active !== shape || _notesActive { deck.endTextSession() }
        _notesActive = false
        _active = shape
        if shape != nil { deck.beginTextSession() }
        _point(at: shape?.text, theme: shape?.textTheme)
        if shape == nil { _deckFocus.requestFocus() }
        setState {}
    }

    private func _endEditing() {
        guard _active != nil || _notesActive else { return }
        FocusManager.instance.focusedNode?.unfocus()
        _activate(nil)
    }

    private func _textChanged() {
        let s = _summarize()
        guard s != session.summary else { return }
        setState { session.summary = s }
    }

    private func _undo() {
        if (_active != nil || _notesActive) && session.controller.canUndo {
            session.controller.undo()
        } else {
            _endEditing()
            deck.undo()
        }
    }

    private func _redo() {
        if (_active != nil || _notesActive) && session.controller.canRedo {
            session.controller.redo()
        } else {
            _endEditing()
            deck.redo()
        }
    }

    private func _deckChanged() {
        // A slide that went away takes its editing with it.
        if let a = _active, !deck.currentSlide.shapes.contains(where: { $0 === a }) {
            _active = nil
            _point(at: nil)
        }
        if _notesActive, session.controller !== deck.currentSlide.notes {
            _notesActive = false
            _point(at: nil)
        }
        session.dirty = deck.edits != _savedEdits
        session.summary = _summarize()
        setState {}
    }

    // MARK: Deck commands

    private func _newDeck() {
        _active = nil
        _point(at: nil)
        deck.newDeck()
        _savedEdits = deck.edits
        session.path = nil
        setState {
            session.dirty = false
            _backstage = nil
        }
    }

    private func _open(_ path: String) {
        let ext = path.pathExtension.lowercased()
        if OfficeFormats.readable.contains(ext) {
            _w.onSwitch(.document, path)
            return
        }
        do {
            guard let data = FileManager.default.contents(atPath: path) else { throw Pptx.ReadError.noPresentation }
            let (state, theme, package) = try Pptx.read(data)
            _endEditing()
            deck.load(state, theme: theme, package: package)
            _savedEdits = deck.edits
            session.path = path
            _recent = OfficeRecent.remember(path, in: _recent)
            setState {
                session.dirty = false
                _backstage = nil
            }
            _flash("Opened \(path.lastPathComponent) — \(deck.slides.count) slides")
        } catch {
            _flash("Could not open \(path.lastPathComponent): \(error)")
            setState { _backstage = nil }
        }
    }

    // MARK: Slide show

    private func _startShow(at index: Int) {
        _endEditing()
        hostSetFullscreen?(true)
        setState { _show = index }
    }

    private func _endShow() {
        hostSetFullscreen?(false)
        setState { _show = nil }
        _deckFocus.requestFocus()
    }

    // MARK: Saving

    private func _save() {
        guard let path = session.path, path.pathExtension.lowercased() == "pptx" else {
            setState { _backstage = .saveAs }
            return
        }
        _saveTo(path)
    }

    private func _saveTo(_ chosen: String) {
        let path = chosen.pathExtension.lowercased() == "pptx" ? chosen : chosen + ".pptx"
        _endEditing()
        do {
            let data = try Pptx.write(deck)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            session.path = path
            _savedEdits = deck.edits
            _recent = OfficeRecent.remember(path, in: _recent)
            setState {
                session.dirty = false
                _backstage = nil
            }
            _flash("Saved \(path.lastPathComponent)")
        } catch {
            _flash("Could not save \(path.lastPathComponent): \(error)")
        }
    }

    /// PDF or a .pptx copy, beside the deck (or in Documents), named after it.
    private func _export(_ ext: String) {
        let base = session.path.map { $0.deletingPathExtension } ?? homeDirectory() + "/Documents/" + session.title.deletingPathExtension
        let target = base + "." + ext
        _endEditing()
        if ext == "pptx" {
            do {
                try Pptx.write(deck).write(to: URL(fileURLWithPath: target), options: .atomic)
                _flash("Exported \(target.lastPathComponent)")
            } catch {
                _flash("Could not export: \(error)")
            }
            setState { _backstage = nil }
            return
        }
        setState { _backstage = nil }
        _flash("Exporting \(target.lastPathComponent)…")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let ok = await SlidesPdf.write(self.deck, cache: self._cache, to: target, title: self.session.title)
            self._flash(ok ? "Exported \(target.lastPathComponent)" : "Could not write \(target.lastPathComponent)")
        }
    }

    private func _insertTextBox() {
        _endEditing()
        let size = deck.slideSize
        let shape = deck.addTextBox(at: Rect.fromLTWH(size.width / 2 - 150, size.height / 2 - 25, 300, 50))
        _focusShape = shape
        _activate(shape)
    }

    private func _select(_ index: Int) {
        _endEditing()
        deck.select(index)
        _deckFocus.requestFocus()
    }

    private func _flash(_ message: String) {
        _statusGeneration += 1
        let gen = _statusGeneration
        setState { _status = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self._statusGeneration == gen else { return }
            self.setState { self._status = nil }
        }
    }

    // MARK: Keys

    /// Keys while no text is being edited: move between slides, add and
    /// remove them, and the app's chords.
    private func _deckKey(_ key: KeyData) -> Bool {
        if _deckChords.track(key) { return false }
        guard key.type == .down || key.type == .repeat else { return false }
        let named = KeyChordTracker.named(key.logical)
        // ⌘↑ / ⌘↓ move the current slide up and down the deck.
        if _deckChords.primary, _paneFocused || _sorter, named == .up || named == .down {
            deck.moveSlide(deck.current, to: deck.current + (named == .up ? -1 : 1))
            return true
        }
        if _sorter {
            switch named {
            case .left, .up: _select(deck.current - 1); _paneFocused = true
            case .right, .down: _select(deck.current + 1); _paneFocused = true
            case .enter: setState { _sorter = false }
            case .delete, .backspace where deck.slides.count > 1: deck.deleteSlide(deck.current)
            default: break
            }
            if [.left, .up, .right, .down, .enter, .delete, .backspace].contains(named) { return true }
        }
        if _deckChords.primary || named == .escape {
            if _shortcut(key, _deckChords.modifiers) { return true }
        }
        // With shapes selected, keys act on them.
        if !deck.selection.isEmpty && !_paneFocused {
            let step = _deckChords.shift ? 12.0 : 2.0
            switch named {
            case .left: deck.nudgeSelection(dx: -step, dy: 0)
            case .right: deck.nudgeSelection(dx: step, dy: 0)
            case .up: deck.nudgeSelection(dx: 0, dy: -step)
            case .down: deck.nudgeSelection(dx: 0, dy: step)
            case .delete, .backspace: deck.deleteSelection()
            case .escape: deck.selectShapes([])
            case .tab: _cycleSelection(back: _deckChords.shift)
            case .enter:
                guard deck.selection.count == 1, let shape = deck.selection.first, shape.text != nil else { return false }
                _editAtEnd(shape)
            default: return false
            }
            return true
        }
        // F5 plays from the beginning, ⇧F5 from here (PowerPoint's keys).
        if named == .function(5) {
            _startShow(at: _deckChords.shift ? deck.current : 0)
            return true
        }
        switch named {
        case .down, .right, .pageDown: _select(deck.current + 1)
        case .up, .left, .pageUp: _select(deck.current - 1)
        case .home: _select(0)
        case .end: _select(deck.slides.count - 1)
        case .enter where _paneFocused: deck.addSlide()
        case .tab where !_paneFocused: _cycleSelection(back: _deckChords.shift)
        case .delete, .backspace:
            guard _paneFocused, deck.slides.count > 1 else { return false }
            deck.deleteSlide(deck.current)
        default: return false
        }
        return true
    }

    /// Tab through the shapes of the slide, as PowerPoint does.
    private func _cycleSelection(back: Bool) {
        let shapes = deck.currentSlide.shapes
        guard !shapes.isEmpty else { return }
        let at = deck.selection.last.flatMap { s in shapes.firstIndex { $0 === s } }
        let next = at.map { (back ? $0 - 1 + shapes.count : $0 + 1) % shapes.count } ?? (back ? shapes.count - 1 : 0)
        deck.selectShapes([shapes[next]])
    }

    /// Start typing into a shape, with the caret at the end of its text.
    private func _editAtEnd(_ shape: SlideShape) {
        _activate(shape)
        FrameCallbackScheduler.shared.addPostFrameCallback { [weak self] _ in
            guard let self, let canvas = self._canvasKey.currentState as? SlideCanvasState,
                  let text = shape.text else { return }
            canvas.focusNode(for: shape).requestFocus()
            let last = text.document.paragraphs.count - 1
            text.moveTo(RichPosition(paragraph: last, offset: text.document.paragraphs[last].length), extend: false)
        }
        PlatformDispatcher.instance.scheduleFrame()
    }

    private func _shortcut(_ key: KeyData, _ mods: KeyModifiers) -> Bool {
        let named = KeyChordTracker.named(key.logical)
        let typing = _active != nil || _notesActive
        // ⌘⇧↩ plays from the beginning, ⌘↩ from here (PowerPoint for Mac).
        if named == .enter, mods.contains(.primary) {
            _startShow(at: mods.contains(.shift) ? 0 : deck.current)
            return true
        }
        if named == .escape {
            if _backstage != nil { setState { _backstage = nil }; return true }
            if typing {
                // Esc leaves the text with its shape still selected.
                let shape = _active
                _endEditing()
                if let shape { deck.selectShapes([shape]) }
                return true
            }
            if !deck.selection.isEmpty { deck.selectShapes([]); return true }
            return false
        }
        guard mods.contains(.primary), !mods.contains(.alt),
              let letter = KeyChordTracker.letter(key.logical) else { return false }
        let c = session.controller
        let shapes = !typing && !deck.selection.isEmpty
        switch letter {
        case "z" where mods.contains(.shift): _redo()
        case "z": _undo()
        case "y": _redo()
        case "n" where mods.contains(.shift): _endEditing(); deck.addSlide()
        case "n": _newDeck()
        case "o": session.onOpen?()
        case "s" where mods.contains(.shift): session.onSaveAs?()
        case "s": session.onSave?()
        case "a" where !typing: deck.selectShapes(deck.currentSlide.shapes)
        case "c" where shapes: _shapeClipboard = deck.copySelection(); _flash("Copied")
        case "x" where shapes: _shapeClipboard = deck.copySelection(); deck.deleteSelection()
        case "v" where !typing && !_shapeClipboard.isEmpty: deck.paste(_shapeClipboard)
        case "d" where shapes: deck.duplicateSelection()
        case "d" where !typing: deck.duplicateSlide(deck.current)
        case "g" where shapes: _flash("Grouping comes with milestone S6")
        case "e": c.setAlignment(.center)
        case "l": c.setAlignment(.left)
        case "r": c.setAlignment(.right)
        case "j": c.setAlignment(.justify)
        default: return false
        }
        return true
    }

    // MARK: Build

    private var _windowTitle = ""

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        session.slidesSorter = _sorter
        let title = "\(session.title)\(session.dirty ? " •" : "") — Slides"
        if title != _windowTitle {
            _windowTitle = title
            hostSetWindowTitle?(title)
        }
        // A text box just inserted takes the caret once its editor exists.
        if let shape = _focusShape {
            _focusShape = nil
            FrameCallbackScheduler.shared.addPostFrameCallback { [weak self] _ in
                guard let canvas = self?._canvasKey.currentState as? SlideCanvasState else { return }
                canvas.focusNode(for: shape).requestFocus()
            }
            PlatformDispatcher.instance.scheduleFrame()
        }
        var column: [Widget] = [
            TitleRow(session: session, searchController: _search, onSearch: { [weak self] _ in
                self?._flash("Find in decks comes with milestone S8")
            }),
            Ribbon(session: session, tab: _tab, collapsed: _ribbonCollapsed,
                   onTab: { [weak self] t in self?.setState { self?._tab = t } },
                   onCollapse: { [weak self] in self?.setState { self?._ribbonCollapsed.toggle() } }),
        ]
        var work: [Widget] = [Expanded(child: SlideCanvas(
            key: _canvasKey,
            deck: deck, cache: _cache, active: _active,
            onEdit: { [weak self] shape in self?._activate(shape) },
            onShortcut: { [weak self] key, mods in self?._shortcut(key, mods) ?? false },
            spellChecker: session.checkSpelling ? _spelling : nil))]
        if _showNotes { work.append(_notesPane(fluent)) }
        if _sorter {
            column.append(Expanded(child: _sorterView(fluent)))
        } else {
            column.append(Expanded(child: Row(crossAxisAlignment: .stretch, children: [
                _thumbnailPane(fluent),
                Expanded(child: Column(crossAxisAlignment: .stretch, children: work)),
            ])))
        }
        column.append(_statusBar(fluent))

        let window = ColoredBox(color: fluent.scaffoldBackgroundColor,
                                child: Column(crossAxisAlignment: .stretch, children: column))
        if let start = _show {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SlideShowView(
                    deck: deck, images: _cache, start: start,
                    onEnd: { [weak self] in self?._endShow() })),
            ])
        }
        guard let page = _backstage else { return window }
        return Stack(children: [
            window,
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Backstage(
                session: session, page: page, recent: _recent,
                onPage: { [weak self] p in self?.setState { self?._backstage = p } },
                onClose: { [weak self] in self?.setState { self?._backstage = nil } },
                onOpenPath: { [weak self] path in self?._open(path) },
                onSavePath: { [weak self] path in self?._saveTo(path) },
                onPicturePath: { [weak self] _ in self?._flash("Pictures on slides are milestone S6") })),
        ])
    }

    private let _canvasKey = GlobalKey<State<StatefulWidget>>()

    // MARK: Thumbnails

    private func _thumbnailPane(_ fluent: FluentThemeData) -> Widget {
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        let thumbW = 168.0
        let thumbH = (thumbW * deck.slideSize.height / deck.slideSize.width).rounded()
        var items: [Widget] = []
        for (i, slide) in deck.slides.enumerated() {
            let current = i == deck.current
            let number = Text("\(i + 1)", style: fluent.typography.caption?.copyWith(
                color: slide.hidden ? fluent.resources.textFillColorDisabled : fluent.resources.textFillColorPrimary))
            let frame = DecoratedBox(
                decoration: BoxDecoration(border: Border.all(
                    color: current ? accent : fluent.resources.controlStrokeColorDefault,
                    width: current ? 2.5 : 1)),
                child: Padding(padding: EdgeInsets(all: current ? 1 : 2.5), child: SizedBox(
                    width: thumbW, height: thumbH,
                    child: Opacity(opacity: slide.hidden ? 0.45 : 1, child: CustomPaint(
                        painter: SlidePainter(slide: slide, theme: deck.theme, slideSize: deck.slideSize,
                                              revision: deck.revision, cache: _cache),
                        child: SizedBox(expand: ()))))))
            // The insertion line while a thumbnail is dragged over this slot.
            let dropHere = _thumbDrag.map { $0.moved && $0.to == i && $0.to != $0.from } ?? false
            let dropAbove = dropHere && (_thumbDrag!.to < _thumbDrag!.from)
            let line = SizedBox(width: thumbW, height: 3, child: ColoredBox(
                color: dropHere ? accent : Color(0x00000000), child: SizedBox(expand: ())))
            items.append(Listener(
                onPointerDown: { [weak self] e in
                    guard let self, let context = self.context else { return }
                    self._thumbDown(i, e, context: context)
                },
                onPointerMove: { [weak self] e in self?._thumbMove(e.position, itemHeight: thumbH + 18) },
                onPointerUp: { [weak self] e in
                    self?._thumbMove(e.position, itemHeight: thumbH + 18)
                    self?._thumbUp()
                },
                behavior: .opaque,
                child: Padding(padding: EdgeInsets(left: 6, top: 3, right: 10, bottom: 3), child: Row(
                    crossAxisAlignment: .start, children: [
                        SizedBox(width: 20, height: nil, child: Padding(
                            padding: EdgeInsets(left: 0, top: 5, right: 4, bottom: 0),
                            child: Align(alignment: Alignment.topRight, child: number))),
                        Column(crossAxisAlignment: .start, children: [
                            dropAbove ? line : SizedBox(width: thumbW, height: 3, child: nil),
                            frame,
                            !dropAbove ? line : SizedBox(width: thumbW, height: 3, child: nil),
                        ]),
                    ]))))
        }
        return SizedBox(width: thumbW + 46, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.solidBackgroundFillColorBase,
                border: Border(right: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: SingleChildScrollView(child: Padding(
                padding: EdgeInsets(left: 0, top: 6, right: 0, bottom: 12),
                child: Column(crossAxisAlignment: .start, children: items)))))
    }

    private func _thumbDown(_ index: Int, _ e: PointerDownEvent, context: any BuildContext) {
        if e.buttons & kSecondaryMouseButton != 0 {
            _select(index)
            _paneFocused = true
            _showThumbMenu(at: e.position, context: context)
            return
        }
        _select(index)
        _paneFocused = true
        _thumbDrag = (index, e.position.dy, e.position.dx, index, false)
    }

    private func _thumbMove(_ position: Offset, itemHeight: Double) {
        guard var drag = _thumbDrag else { return }
        let dy = position.dy - drag.startY
        if !drag.moved && abs(dy) < 6 { return }
        drag.moved = true
        drag.to = max(0, min(deck.slides.count - 1, drag.from + Int((dy / itemHeight).rounded())))
        if drag.to != _thumbDrag?.to || !(_thumbDrag?.moved ?? false) {
            _thumbDrag = drag
            setState {}
        } else {
            _thumbDrag = drag
        }
    }

    private func _thumbUp() {
        guard let drag = _thumbDrag else { return }
        _thumbDrag = nil
        if drag.moved, drag.to != drag.from { deck.moveSlide(drag.from, to: drag.to) } else { setState {} }
    }

    /// The thumbnail pane's right-click menu.
    private func _showThumbMenu(at point: Offset, context: any BuildContext) {
        let i = deck.current
        let hidden = deck.currentSlide.hidden
        var items: [MenuFlyoutItemBase] = [
            MenuFlyoutItem(text: Text("New Slide"), onPressed: { [weak self] in self?.deck.addSlide() }),
            MenuFlyoutItem(text: Text("Duplicate Slide"), onPressed: { [weak self] in self?.deck.duplicateSlide(i) }),
            MenuFlyoutItem(text: Text("Delete Slide"),
                           onPressed: deck.slides.count > 1 ? { [weak self] in self?.deck.deleteSlide(i) } : nil),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text(hidden ? "Show Slide" : "Hide Slide"),
                           onPressed: { [weak self] in self?.deck.toggleHidden(i) }),
            MenuFlyoutSeparator(),
        ]
        for kind in SlideLayoutKind.allCases {
            items.append(MenuFlyoutItem(text: Text("Layout: \(kind.name)"),
                                        onPressed: kind == deck.currentSlide.layout ? nil
                                            : { [weak self] in self?.deck.applyLayout(kind, to: i) }))
        }
        _thumbMenu.showFlyout(in: context, at: point) { _ in MenuFlyout(items: items) }
    }

    // MARK: Slide Sorter

    /// Every slide as a large thumbnail, in reading order. Click selects, a
    /// double click opens the slide in Normal view; ⌘↑/⌘↓ and the
    /// thumbnail pane's drag reorder.
    private func _sorterView(_ fluent: FluentThemeData) -> Widget {
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        let w = 240.0
        let h = (w * deck.slideSize.height / deck.slideSize.width).rounded()
        var tiles: [Widget] = []
        for (i, slide) in deck.slides.enumerated() {
            let current = i == deck.current
            tiles.append(GestureDetector(
                onTap: { [weak self] in
                    guard let self else { return }
                    let now = Date()
                    if let last = self._lastSorterTap, last.index == i, now.timeIntervalSince(last.at) < 0.4 {
                        self._lastSorterTap = nil
                        self.setState { self._sorter = false }
                        return
                    }
                    self._lastSorterTap = (i, now)
                    self._select(i)
                    self._paneFocused = true
                },
                child: Padding(padding: EdgeInsets(all: 12), child: Column(crossAxisAlignment: .start, children: [
                    DecoratedBox(
                        decoration: BoxDecoration(border: Border.all(
                            color: current ? accent : fluent.resources.controlStrokeColorDefault,
                            width: current ? 3 : 1)),
                        child: Padding(padding: EdgeInsets(all: current ? 1 : 3), child: SizedBox(
                            width: w, height: h,
                            child: Opacity(opacity: slide.hidden ? 0.45 : 1, child: CustomPaint(
                                painter: SlidePainter(slide: slide, theme: deck.theme, slideSize: deck.slideSize,
                                                      revision: deck.revision, cache: _cache),
                                child: SizedBox(expand: ())))))),
                    Chrome.vgap(4),
                    Text("\(i + 1)\(slide.hidden ? "  (hidden)" : "")", style: fluent.typography.caption),
                ]))))
        }
        let dark = fluent.brightness == .dark
        return ColoredBox(color: dark ? Color(0xFF202020) : Color(0xFFE6E6E6), child: SingleChildScrollView(
            child: Padding(padding: EdgeInsets(all: 16), child: Wrap(children: tiles))))
    }

    // MARK: Notes

    private func _notesPane(_ fluent: FluentThemeData) -> Widget {
        let slide = deck.currentSlide
        let dark = fluent.brightness == .dark
        _notesTheme.textColor = dark ? Color(0xFFF0F0F0) : Color(0xFF1B1B1B)
        _notesTheme.caretColor = _notesTheme.textColor
        let empty = slide.notes.document.paragraphs.allSatisfy { $0.text.isEmpty }
        // Prompt and editor every build, so the editor never remounts.
        var stack: [Widget] = []
        stack.append(Positioned(left: 14, top: 10, right: 14, height: 24, child: IgnorePointer(child: Text(
            empty && !_notesActive ? "Click to add notes" : "",
            style: fluent.typography.body?.copyWith(color: fluent.resources.textFillColorSecondary)))))
        stack.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Listener(
            onPointerDown: { [weak self] _ in
                guard let self, !self._notesActive else { return }
                self.deck.endTextSession()
                self._active = nil
                self._paneFocused = false
                self._notesActive = true
                self.deck.selectShapes([])
                self.deck.beginTextSession()
                self._point(at: slide.notes, theme: self._notesTheme)
                self.setState {}
            },
            behavior: .translucent,
            child: RichEditable(
                key: ValueKey(slide.id),
                controller: slide.notes, theme: _notesTheme,
                padding: EdgeInsets(left: 14, top: 10, right: 14, bottom: 10),
                focusNode: _notesFocus, autofocus: false, backgroundColor: nil,
                onShortcut: { [weak self] key, mods in self?._shortcut(key, mods) ?? false },
                spellChecker: session.checkSpelling ? _spelling : nil))))
        return SizedBox(width: nil, height: 104, child: DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.solidBackgroundFillColorBase,
                border: Border(top: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: Stack(children: stack)))
    }

    // MARK: Status bar

    private func _statusBar(_ fluent: FluentThemeData) -> Widget {
        let caption = fluent.typography.caption
        let dim = caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        var left: [Widget] = [
            Text("Slide \(deck.current + 1) of \(deck.slides.count)"
                 + (deck.currentSlide.hidden ? " (hidden)" : ""), style: caption),
            Chrome.gap(20),
            Text("English (United States)", style: dim),
        ]
        if let message = _status {
            left.append(Chrome.gap(20))
            left.append(Text(message, style: dim))
        }
        let right: [Widget] = [
            Chrome.textToggle("Notes", _showNotes, fluent, style: caption) { [weak self] in
                self?.setState { self?._showNotes.toggle() }
            },
            Chrome.gap(8),
            Chrome.toggle(FluentSystemIcons.onePage, "Normal", !_sorter, fluent) { [weak self] in
                self?.session.onSlidesView?(false)
            },
            Chrome.toggle(FluentSystemIcons.grid, "Slide Sorter", _sorter, fluent) { [weak self] in
                self?.session.onSlidesView?(true)
            },
            Chrome.gap(8),
            Chrome.icon(FluentSystemIcons.pageFit, "Fit slide to window", fluent) {},
        ]
        return DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.solidBackgroundFillColorBase,
                border: Border(top: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 2, right: 8, bottom: 2), child: Row(
                crossAxisAlignment: .center,
                children: left + [Expanded(child: SizedBox(width: 0, height: 0, child: nil))] + right)))
    }
}
