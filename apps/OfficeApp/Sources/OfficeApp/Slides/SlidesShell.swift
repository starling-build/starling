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
        session.onSave = { [weak self] in self?._flash("Saving decks as .pptx is the next milestone") }
        session.onSaveAs = { [weak self] in self?._flash("Saving decks as .pptx is the next milestone") }
        session.onExport = { [weak self] _ in self?._flash("PDF export of decks comes with .pptx") }
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
        session.onSlideShow = { [weak self] _ in self?._flash("The slide show is milestone S5") }
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
        session.summary = session.summarize()
    }

    private func _activate(_ shape: SlideShape?) {
        _paneFocused = false
        _notesActive = false
        _active = shape
        _point(at: shape?.text, theme: shape?.textTheme)
        if shape == nil { _deckFocus.requestFocus() }
        setState {}
    }

    private func _textChanged() {
        let s = session.summarize()
        guard s != session.summary else { return }
        setState { session.summary = s }
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
        session.dirty = true
        setState {}
    }

    // MARK: Deck commands

    private func _newDeck() {
        _active = nil
        _point(at: nil)
        deck.newDeck()
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
        _flash("Opening .pptx is the next milestone")
        setState { _backstage = nil }
    }

    private func _insertTextBox() {
        let size = deck.slideSize
        let shape = deck.addTextBox(at: Rect.fromLTWH(size.width / 2 - 150, size.height / 2 - 25, 300, 50))
        _focusShape = shape
        _activate(shape)
    }

    private func _select(_ index: Int) {
        FocusManager.instance.focusedNode?.unfocus()
        _active = nil
        _notesActive = false
        _point(at: nil)
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
        if _deckChords.primary || named == .escape {
            if _shortcut(key, _deckChords.modifiers) { return true }
        }
        switch named {
        case .down, .right, .pageDown: _select(deck.current + 1)
        case .up, .left, .pageUp: _select(deck.current - 1)
        case .home: _select(0)
        case .end: _select(deck.slides.count - 1)
        case .enter where _paneFocused: deck.addSlide()
        case .delete, .backspace:
            guard _paneFocused, deck.slides.count > 1 else { return false }
            deck.deleteSlide(deck.current)
        default: return false
        }
        return true
    }

    private func _shortcut(_ key: KeyData, _ mods: KeyModifiers) -> Bool {
        let named = KeyChordTracker.named(key.logical)
        if named == .escape {
            if _backstage != nil { setState { _backstage = nil }; return true }
            if _active != nil || _notesActive {
                FocusManager.instance.focusedNode?.unfocus()
                _activate(nil)
                return true
            }
            return false
        }
        guard mods.contains(.primary), !mods.contains(.alt),
              let letter = KeyChordTracker.letter(key.logical) else { return false }
        let c = session.controller
        switch letter {
        case "n" where mods.contains(.shift): deck.addSlide()
        case "n": _newDeck()
        case "o": session.onOpen?()
        case "s": session.onSave?()
        case "d" where _active == nil && !_notesActive: deck.duplicateSlide(deck.current)
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
            onActivate: { [weak self] shape in self?._activate(shape) },
            onShortcut: { [weak self] key, mods in self?._shortcut(key, mods) ?? false },
            spellChecker: session.checkSpelling ? _spelling : nil))]
        if _showNotes { work.append(_notesPane(fluent)) }
        column.append(Expanded(child: Row(crossAxisAlignment: .stretch, children: [
            _thumbnailPane(fluent),
            Expanded(child: Column(crossAxisAlignment: .stretch, children: work)),
        ])))
        column.append(_statusBar(fluent))

        let window = ColoredBox(color: fluent.scaffoldBackgroundColor,
                                child: Column(crossAxisAlignment: .stretch, children: column))
        guard let page = _backstage else { return window }
        return Stack(children: [
            window,
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Backstage(
                session: session, page: page, recent: _recent,
                onPage: { [weak self] p in self?.setState { self?._backstage = p } },
                onClose: { [weak self] in self?.setState { self?._backstage = nil } },
                onOpenPath: { [weak self] path in self?._open(path) },
                onSavePath: { [weak self] _ in self?._flash("Saving decks as .pptx is the next milestone") },
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
                child: Padding(padding: EdgeInsets(all: current ? 2.5 : 1), child: SizedBox(
                    width: thumbW, height: thumbH,
                    child: Opacity(opacity: slide.hidden ? 0.45 : 1, child: CustomPaint(
                        painter: SlidePainter(slide: slide, theme: deck.theme, slideSize: deck.slideSize,
                                              revision: deck.revision, cache: _cache),
                        child: SizedBox(expand: ()))))))
            items.append(GestureDetector(
                onTap: { [weak self] in
                    guard let self else { return }
                    self._select(i)
                    self._paneFocused = true
                },
                child: Padding(padding: EdgeInsets(left: 6, top: 6, right: 10, bottom: 6), child: Row(
                    crossAxisAlignment: .start, children: [
                        SizedBox(width: 20, height: nil, child: Padding(
                            padding: EdgeInsets(left: 0, top: 2, right: 4, bottom: 0),
                            child: Align(alignment: Alignment.topRight, child: number))),
                        frame,
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
                self._active = nil
                self._paneFocused = false
                self._notesActive = true
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
            Text("Slide \(deck.current + 1) of \(deck.slides.count)", style: caption),
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
            Chrome.toggle(FluentSystemIcons.onePage, "Normal", true, fluent) {},
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
