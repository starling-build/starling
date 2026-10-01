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
    /// A new deck on request (Backstage), never an untitled recovery copy.
    let startBlank: Bool
    let onSwitch: (DocumentKind, String?) -> Void

    init(initialPath: String?, startBlank: Bool = false, onSwitch: @escaping (DocumentKind, String?) -> Void) {
        self.initialPath = initialPath
        self.startBlank = startBlank
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
    /// The open deck came from a recovery copy: AutoSave leaves the file
    /// alone until the user saves.
    private var _recovered = false
    private var _autosaveGeneration = 0
    private var _lastAutosaveEdits = -1
    /// Shapes copied with ⌘C/⌘X while no text was being edited.
    private var _shapeClipboard: [ShapeState] = []
    /// Normal (canvas and notes) or Slide Sorter (a grid of every slide).
    private var _sorter = false
    /// The slide show, when running: the slide it started from.
    private var _show: Int? = nil
    private var _presenter = false
    /// Where the next picture from the picture panel goes.
    private var _pictureForBackground = false
    private var _hadPicture = false
    private var _hadChart: SlideShape? = nil
    /// The chart data grid is open (for whichever chart is selected).
    private var _chartData = false
    /// The Header & Footer dialog is up.
    private var _headerFooter = false
    /// The Animation Pane is open beside the slide.
    private var _animationPane = false
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
    /// Find and Replace across the deck.
    private var _findOpen = false
    private var _findReplace = false
    private var _findStatus = ""
    private let _findQuery = TextEditingController()
    private let _findReplacement = TextEditingController()
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
        if let path = _w.initialPath {
            _open(path)
        } else if !_w.startBlank, let data = FileManager.default.contents(atPath: _recoveryPath(for: nil)),
                  let (state, theme, package) = try? Pptx.read(data) {
            // Last time ended with an unsaved untitled deck.
            deck.load(state, theme: theme, package: package)
            _recovered = true
            _savedEdits = deck.edits - 1
            _lastAutosaveEdits = deck.edits
            session.dirty = true
            _flash("Restored an unsaved presentation — Save to keep it")
        }
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
        session.onInsertPicture = { [weak self] in
            guard let self else { return }
            self._pictureForBackground = false
            self.setState { self._backstage = .insertPicture }
        }
        session.onHeaderFooter = { [weak self] in
            guard let self else { return }
            self._endEditing()
            self.setState { self._headerFooter = true }
        }
        session.onToggleAutoSave = { [weak self] in
            guard let self else { return }
            self.setState { self.session.autoSave.toggle() }
            self._flash(self.session.autoSave ? "AutoSave on" : "AutoSave off — a recovery copy is still kept")
        }
        session.onAnimationPane = { [weak self] in
            self?.setState { self?._animationPane.toggle() }
        }
        session.onChartData = { [weak self] show in
            self?.setState { self?._chartData = show }
        }
        session.onInsertTable = { [weak self] rows, columns in
            guard let self else { return }
            self._endEditing()
            let table = self.deck.addTable(rows: rows, columns: columns)
            self._editAtStart(table)
        }
        session.onBackgroundPicture = { [weak self] in
            guard let self else { return }
            self._pictureForBackground = true
            self.setState { self._backstage = .insertPicture }
        }
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
        session.onPresenterView = { [weak self] in
            guard let self else { return }
            self._startShow(at: self.deck.current, presenter: true)
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

    // MARK: Find and Replace

    private func _openFind(replace: Bool) {
        let c = session.controller
        if (_active != nil || _notesActive), c.hasSelection, !c.selectedText.contains(Character("\n")) {
            _findQuery.text = c.selectedText
        }
        setState {
            _findOpen = true
            _findReplace = replace
            _findStatus = ""
        }
    }

    /// Where the search stands: the slide, the body being edited (or before
    /// the first), and the caret in it.
    private func _findPosition(backwards: Bool) -> (slide: Int, stop: Int, at: RichPosition) {
        let stops = deck.textStops(deck.current)
        let editing: Int? = _notesActive ? stops.count - 1
            : _active.flatMap { a in stops.firstIndex { $0.shape === a } }
        guard let stop = editing else { return (deck.current, backwards ? stops.count : -1, RichPosition(paragraph: 0, offset: 0)) }
        let sel = stops[stop].controller.selection
        return (deck.current, stop, backwards ? sel.start : sel.end)
    }

    private func _findNext(backwards: Bool) {
        let q = _findQuery.text
        let all = deck.matches(q)
        guard !all.isEmpty else { setState { _findStatus = q.isEmpty ? "" : "No matches" }; return }
        let here = _findPosition(backwards: backwards)
        let pick: DeckMatch
        if backwards {
            pick = all.last { $0.isBefore(here.slide, here.stop, here.at) } ?? all.last!
        } else {
            // From the end of the selection: a match that is the selection
            // itself starts before it and is passed over.
            pick = all.first { !$0.isBefore(here.slide, here.stop, here.at) } ?? all.first!
        }
        _show(pick)
        let n = (all.firstIndex(of: pick) ?? 0) + 1
        setState { _findStatus = "\(n) of \(all.count)" }
    }

    /// Go to a match: its slide, its body being edited, the text selected.
    private func _show(_ m: DeckMatch) {
        deck.select(m.slide)
        let stops = deck.textStops(m.slide)
        guard stops.indices.contains(m.stop) else { return }
        if let shape = stops[m.stop].shape {
            deck.selectShapes([shape])
            _activate(shape)
            // The match selected, the keyboard left in the find field:
            // Return there means "next", never "replace this with a break".
            shape.text?.selection = m.selection
        } else {
            deck.endTextSession()
            _active = nil
            _notesActive = true
            deck.selectShapes([])
            deck.beginTextSession()
            let notes = deck.currentSlide.notes
            _point(at: notes, theme: _notesTheme)
            notes.selection = m.selection
        }
        setState {}
    }

    private func _replaceOne() {
        let q = _findQuery.text
        guard !q.isEmpty else { return }
        let c = session.controller
        if (_active != nil || _notesActive), c.hasSelection, c.selectedText.lowercased() == q.lowercased() {
            c.insertText(_findReplacement.text)
        }
        _findNext(backwards: false)
    }

    private func _replaceAll() {
        _endEditing()
        let n = deck.replaceEverywhere(_findQuery.text, with: _findReplacement.text)
        setState { _findStatus = n == 0 ? "No matches" : "Replaced \(n)" }
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

    /// Tables on the current slide take the height their rows need.
    private func _fitTables() {
        for shape in deck.currentSlide.shapes where shape.kind == .table {
            guard let layout = _cache.layout(shape, pxPerPt: 1) else { continue }
            deck.fitHeight(shape, (layout.totalHeight + shape.insets.top + shape.insets.bottom).rounded(.up))
        }
    }

    /// What each autofit shape was last measured at (text revision, frame):
    /// it is measured again only once one of them changes, so a deck opens
    /// at the scales the file says.
    private var _fitSeen: [Int: (revision: Int, frame: Rect)] = [:]

    /// PowerPoint's autofit: the largest of its scale steps at which an
    /// autofit shape's text fits its box.
    private func _autofit() {
        for shape in deck.currentSlide.shapes where shape.autofit {
            guard let text = shape.text else { continue }
            let now = (text.revision, shape.frame)
            guard let seen = _fitSeen[shape.id] else { _fitSeen[shape.id] = now; continue }
            guard seen.revision != now.0 || seen.frame != now.1 else { continue }
            _fitSeen[shape.id] = now
            deck.setFontScale(shape, SlideTextCache.autofitScale(shape))
        }
    }

    private func _deckChanged() {
        _fitTables()
        _autofit()
        // A selected picture opens its tab; leaving it returns Home.
        let picture = deck.selection.contains { $0.picture != nil }
        if picture && !_hadPicture { _tab = .pictureFormat }
        if !picture && _tab == .pictureFormat { _tab = .home }
        _hadPicture = picture
        // Likewise a chart and Chart Design; its data grid closes with it.
        let chart = deck.selectedChart
        if let chart, chart !== _hadChart { _tab = .chartDesign }
        if chart == nil {
            if _tab == .chartDesign { _tab = .home }
            _chartData = false
        }
        _hadChart = chart
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
        if session.dirty && deck.edits != _lastAutosaveEdits {
            _lastAutosaveEdits = deck.edits
            _scheduleAutosave()
        }
        setState {}
    }

    // MARK: AutoSave and recovery

    /// Beside a saved deck as `name.pptx~`; for an untitled one, under the
    /// recovery directory (OfficeRecovery).
    private func _recoveryPath(for path: String?) -> String {
        path.map { $0 + "~" } ?? OfficeRecovery.untitled("pptx")
    }

    /// Two seconds after the last change: AutoSave writes the file itself
    /// when it is on and the deck has one; otherwise the recovery copy is
    /// refreshed — as Writer does.
    private func _scheduleAutosave() {
        #if !os(WASI)
        _autosaveGeneration += 1
        let gen = _autosaveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [weak self] in
            guard let self, self.mounted, self._autosaveGeneration == gen, self.session.dirty, self._show == nil else { return }
            guard let data = try? Pptx.write(self.deck) else { return }
            if self.session.autoSave, !self._recovered, let path = self.session.path,
               path.pathExtension.lowercased() == "pptx" {
                do {
                    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                    self._savedEdits = self.deck.edits
                    try? FileManager.default.removeItem(atPath: self._recoveryPath(for: path))
                    self.setState { self.session.dirty = false }
                    return
                } catch {
                    self._flash("AutoSave could not write: \(error)")
                }
            }
            try? data.write(to: URL(fileURLWithPath: self._recoveryPath(for: self.session.path)), options: .atomic)
        }
        #endif
    }

    /// A recovery copy newer than the file: the last session ended with
    /// unsaved changes.
    private func _recoveryIfNewer(than path: String) -> String? {
        let recovery = _recoveryPath(for: path)
        let fm = FileManager.default
        guard let r = try? fm.attributesOfItem(atPath: recovery)[.modificationDate] as? Date,
              let f = try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date, r > f else { return nil }
        return recovery
    }

    /// Saved, or deliberately discarded: no copy to come back to.
    private func _dropRecovery() {
        try? FileManager.default.removeItem(atPath: _recoveryPath(for: session.path))
        _recovered = false
    }

    // MARK: Deck commands

    private func _newDeck() {
        _active = nil
        _point(at: nil)
        _autosaveGeneration += 1
        _recovered = false
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
            _autosaveGeneration += 1
            // Unsaved changes from last time win over the file, said aloud;
            // a copy that does not read never blocks the file.
            var recovered: (DeckState, DeckTheme, PptxPackage)? = nil
            if let r = _recoveryIfNewer(than: path) {
                recovered = FileManager.default.contents(atPath: r).flatMap { try? Pptx.read($0) }
                if recovered == nil { try? FileManager.default.removeItem(atPath: r) }
            }
            guard let data = FileManager.default.contents(atPath: path) else { throw Pptx.ReadError.noPresentation }
            let (state, theme, package) = try recovered ?? Pptx.read(data)
            _endEditing()
            deck.load(state, theme: theme, package: package)
            session.path = path
            _recovered = recovered != nil
            _savedEdits = recovered == nil ? deck.edits : deck.edits - 1
            _lastAutosaveEdits = deck.edits
            _recent = OfficeRecent.remember(path, in: _recent)
            setState {
                session.dirty = recovered != nil
                _backstage = nil
            }
            _flash(recovered != nil ? "Restored unsaved changes to \(path.lastPathComponent) — Save to keep them"
                                    : "Opened \(path.lastPathComponent) — \(deck.slides.count) slides")
        } catch {
            _flash("Could not open \(path.lastPathComponent): \(error)")
            setState { _backstage = nil }
        }
    }

    // MARK: Slide show

    private func _startShow(at index: Int, presenter: Bool = false) {
        _endEditing()
        hostSetFullscreen?(true)
        setState {
            _show = index
            _presenter = presenter
        }
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
            // Saved: the copy beside the old name (or the untitled one) goes.
            _dropRecovery()
            session.path = path
            _dropRecovery()
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

    private func _insertPicture(_ path: String) {
        setState { _backstage = nil }
        guard let data = FileManager.default.contents(atPath: path) else {
            _flash("Could not read \(path.lastPathComponent)")
            return
        }
        let forBackground = _pictureForBackground
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let codec = try await instantiateImageCodec([UInt8](data))
                let frame = try await codec.getNextFrame()
                codec.dispose()
                // Pixels read as 96 per inch, the convention pictures use.
                let w = Double(frame.image.width) * 0.75, h = Double(frame.image.height) * 0.75
                frame.image.dispose()
                let image = ImageAttachment(data: data, width: w, height: h, name: path.lastPathComponent,
                                            naturalWidth: w, naturalHeight: h)
                self._endEditing()
                if forBackground {
                    self.deck.setBackground(SlideFill(image: image))
                } else {
                    self.deck.addPicture(image, naturalSize: Size(w, h))
                }
                self._deckFocus.requestFocus()
                self._flash("Inserted \(path.lastPathComponent)")
            } catch {
                self._flash("Not a picture Slides can decode: \(path.lastPathComponent)")
            }
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
        // F5 plays from the beginning, ⇧F5 from here, ⌥F5 in presenter
        // view (PowerPoint's keys).
        if named == .function(5) {
            _startShow(at: _deckChords.shift || _deckChords.alt ? deck.current : 0, presenter: _deckChords.alt)
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

    /// Start typing into a shape at the start of its text (a new table's
    /// first cell).
    private func _editAtStart(_ shape: SlideShape) {
        _activate(shape)
        FrameCallbackScheduler.shared.addPostFrameCallback { [weak self] _ in
            guard let self, let canvas = self._canvasKey.currentState as? SlideCanvasState else { return }
            canvas.focusNode(for: shape).requestFocus()
            shape.text?.moveTo(.start, extend: false)
        }
        PlatformDispatcher.instance.scheduleFrame()
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
        case "f": _openFind(replace: false)
        case "h": _openFind(replace: true)
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
                guard let self else { return }
                self._findQuery.text = self._search.text
                self._openFind(replace: false)
                self._findNext(backwards: false)
            }),
            Ribbon(session: session, tab: _tab, collapsed: _ribbonCollapsed,
                   onTab: { [weak self] t in self?.setState { self?._tab = t } },
                   onCollapse: { [weak self] in self?.setState { self?._ribbonCollapsed.toggle() } }),
        ]
        if _findOpen {
            column.append(FindBar(session: session, query: _findQuery, replacement: _findReplacement,
                                  showReplace: _findReplace, status: _findStatus,
                                  onNext: { [weak self] back in self?._findNext(backwards: back) },
                                  onReplace: { [weak self] in self?._replaceOne() },
                                  onReplaceAll: { [weak self] in self?._replaceAll() },
                                  onClose: { [weak self] in self?.setState { self?._findOpen = false } }))
        }
        var work: [Widget] = [Expanded(child: SlideCanvas(
            key: _canvasKey,
            deck: deck, cache: _cache, active: _active,
            onEdit: { [weak self] shape in self?._activate(shape) },
            onShortcut: { [weak self] key, mods in self?._shortcut(key, mods) ?? false },
            spellChecker: session.checkSpelling ? _spelling : nil,
            animationBadges: _tab == .animations || _animationPane))]
        if _showNotes { work.append(_notesPane(fluent)) }
        if _sorter {
            column.append(Expanded(child: _sorterView(fluent)))
        } else {
            var row: [Widget] = [
                _thumbnailPane(fluent),
                Expanded(child: Column(crossAxisAlignment: .stretch, children: work)),
            ]
            if _animationPane {
                row.append(AnimationPane(deck: deck, onClose: { [weak self] in self?.setState { self?._animationPane = false } }))
            }
            if _chartData, let chart = deck.selectedChart {
                row.append(ChartDataPane(key: ValueKey("chart data \(chart.id)"), deck: deck, shape: chart,
                                         onClose: { [weak self] in self?.setState { self?._chartData = false } }))
            }
            column.append(Expanded(child: Row(crossAxisAlignment: .stretch, children: row)))
        }
        column.append(_statusBar(fluent))

        let window = ColoredBox(color: fluent.scaffoldBackgroundColor,
                                child: Column(crossAxisAlignment: .stretch, children: column))
        if let start = _show {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SlideShowView(
                    deck: deck, images: _cache, start: start, presenter: _presenter,
                    onEnd: { [weak self] in self?._endShow() })),
            ])
        }
        if _headerFooter {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: HeaderFooterDialog(
                    initial: deck.headerFooter(of: deck.currentSlide),
                    onApply: { [weak self] hf, all in
                        self?.deck.applyHeaderFooter(hf, toAll: all)
                        self?.setState { self?._headerFooter = false }
                    },
                    onCancel: { [weak self] in self?.setState { self?._headerFooter = false } })),
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
                onPicturePath: { [weak self] path in self?._insertPicture(path) })),
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
