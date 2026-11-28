// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Slides window: title row and ribbon (shared with Writer), then the
// thumbnail pane, the slide canvas and the notes pane, then the status bar.
// Backstage is Writer's, with the deck's own New.

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation
#if os(WASI)
import FlutterWeb
#endif

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
    private let _leakProbe = LeakProbe("SlidesShellState")
    let session = OfficeSession(kind: .presentation)
    private var deck: DeckController { session.deck! }
    private let _cache = SlideTextCache()
    /// The text the ribbon acts on when no body is being edited: nothing
    /// typed here ever shows.
    private let _scratch = RichDocumentController()
    /// What `_scratch` last showed of the selected shapes (deck revision, shape ids), so it is loaded again only when they change.
    private var _scratchShows: (revision: Int, ids: [Int])? = nil
    private var _active: SlideShape? = nil
    private var _notesActive = false
    // Outline view: the left rail becomes one editable list of titles and bodies.
    private var _outline = false
    private let _outlineCtl = RichDocumentController()
    private let _outlineFocus = FocusNode(debugLabel: "slide outline")
    private var _outlineSyncing = false
    private let _outlineTheme: RichTextTheme = {
        let t = RichTextTheme(fontFamily: "Calibri", fontSize: 13, headingColor: nil)
        t.fontFamilyResolver = OfficeFonts.drawn
        return t
    }()
    private var _focusShape: SlideShape? = nil
    private let _deckFocus = FocusNode(debugLabel: "slides deck")
    private let _deckChords = KeyChordTracker()
    private let _notesFocus = FocusNode(debugLabel: "slide notes")
    private let _notesTheme: RichTextTheme = {
        let t = RichTextTheme(fontFamily: "Calibri", fontSize: 12, headingColor: nil)
        t.fontFamilyResolver = OfficeFonts.drawn
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
    /// The edit count whose copy the browser page already holds: a page hide asks again, and an unchanged
    /// deck is not rewritten.
    private var _keptEdits: Int?
    /// Shapes copied with ⌘C/⌘X while no text was being edited.
    /// Normal (canvas and notes) or Slide Sorter (a grid of every slide).
    private var _sorter = false
    /// The slide show, when running: the slide it started from.
    private var _show: Int? = nil
    private var _presenter = false
    /// Where the next picture from the picture panel goes.
    private var _pictureForBackground = false
    /// Set while the picker is open for a shape's picture (false) or texture (true) fill.
    private var _pictureForShapeFill: Bool? = nil
    /// Set while the picker is open for Change Picture: the chosen file replaces the selected pictures.
    private var _pictureForChange = false
    private var _hadPicture = false
    private var _hadTable = false
    private var _hadChart: SlideShape? = nil
    /// The chart data grid is open (for whichever chart is selected).
    private var _chartData = false
    /// The Header & Footer dialog is up.
    private var _headerFooter = false
    private var _setUpShow = false
    private var _rehearsing = false
    private var _customShowsOpen = false
    /// Add or Rename Section: the dialog's title, the name it starts with and what OK does with it.
    private var _sectionDialog: (title: String, initial: String, apply: (String) -> Void)? = nil
    /// Paste Special is open on this clipboard (S-ED-1 step 3).
    private var _pasteSpecialData: ClipboardData? = nil
    /// The Paste Options menu's K, U and T while it is open.
    private var _pasteKeys: Int? = nil
    private var _slideSize = false
    private var _slideSizeInitial = Size(960, 540)
    /// Font Color > More Colors is open.
    private var _colorOpen = false
    /// More Colors… from Shape Fill (false) or Shape Outline (true), while its dialog is up.
    private var _shapeColorFor: Bool?
    private var _altText = false
    /// View > Zoom (or the status bar's percent) opened the Zoom dialog.
    private var _zoomDialog = false
    private var _cellMargins = false
    /// The Insert Hyperlink dialog is up (text being edited, or the selected shapes).
    private var _linkOpen = false
    private var _textOptions = false
    /// The Animation Pane is open beside the slide.
    private var _animationPane = false
    private var _selectionPane = false
    private var _formatShape = false
    private var _formatBackground = false
    /// A thumbnail being dragged to a new place: where it started, the
    /// pointer's start, and where it would land.
    /// A slide dragged in the sorter: where it started, which slot it is over, and whether it has moved.
    private var _sorterDrag: (from: Int, startX: Double, startY: Double, to: Int, moved: Bool)? = nil
    /// How many tiles a sorter row holds (read back from the laid-out grid).
    private var _sorterPerRow = 1
    private var _thumbDrag: (from: Int, startY: Double, startX: Double, to: Int, moved: Bool)? = nil
    private let _thumbMenu = FlyoutController()
    /// A finger held on a thumbnail, or two fingers tapped on it, open its menu as a right click does.
    private let _thumbTouch = TouchMenuTrigger()
    /// The thumbnail pane's scroll, and the slide it was last brought to:
    /// the pane follows the current slide when that changes (arrow keys, a
    /// show that ended elsewhere, Find), and is left alone otherwise so the
    /// wheel can look around.
    private let _thumbScroll = ScrollController()
    private var _thumbShown = -1
    private var _thumbRetries = 0
    private var _f5Token: Int? = nil
    private let _sorterScroll = ScrollController()
    private var _sorterShown = -1
    private var _sorterPosition: ObjectIdentifier? = nil
    private var _thumbPosition: ObjectIdentifier? = nil
    /// Double-click in the sorter, detected by hand: registering
    /// onDoubleTap kills taps on the DRM embedder (CLAUDE.md).
    private var _lastSorterTap: (index: Int, at: Date)? = nil
    private var _tab = RibbonTab.home
    private var _ribbonCollapsed = false
    private var _backstage: BackstagePage? = nil
    private var _status: String? = nil
    private var _statusGeneration = 0
    private var _showNotes = true
    /// The window is narrower than a rail and a slide fit side by side (a Split View pane on an iPad, 375 pt): the
    /// thumbnail rail is hidden so the slide gets the width (the sorter still shows every slide).
    private var _narrow = false
    /// In a narrow window the rail comes back on request (the status bar's "Slides" button).
    private var _narrowRail = false
    private static let narrowBelow = 600.0
    private var _recent: [String] = []
    /// In a browser tab: the page's handle on the file the deck came from or was saved to, so Save writes back
    /// into it (web-parity 4); nil when Save must ask for a place or download.
    private var _browserHandle: Int?
    private let _search = TextEditingController()
    /// Find and Replace across the deck.
    private var _findOpen = false
    private var _symbolOpen = false
    private var _printOpen = false
    private var _shortcutsOpen = false
    private let _findQuery = TextEditingController()
    private let _spelling: RichSpellChecker? = makeSpellChecker()

    private var _w: SlidesShell { widget as! SlidesShell }

    // MARK: Lifecycle

    override func initState() {
        super.initState()
        OfficeFonts.register()
        bind(_deckFocus)
        trackDocumentPath(session)
        bind(_notesFocus)
        bind(_outlineFocus)
        _outlineCtl.addListener({ [weak self] in self?._outlineEdited() }, owner: self)
        _recent = OfficeHost.browserRecent?.names() ?? OfficeRecent.load()
        _wire()
        officeScene.registerFlush(owner: self) { [weak self] in self?._autosaveNow() }
        officeScene.setPictureDrop({ [weak self] path in self?._insertPicture(path) }, owner: self)
        deck.addListener({ [weak self] in self?._deckChanged() }, owner: self)
        _publishToolbar()
        _cache.onImageDecoded = { [weak self] in
            guard let self, self.mounted else { return }
            self.setState {}
        }
        _point(at: nil)
        _deckFocus.onKeyData = { [weak self] key in self?._deckKey(key) ?? false }
        // A chord that moves the keyboard elsewhere — Ctrl+F opens the find
        // box — takes the modifier's key-up with it, and the deck went on
        // believing Ctrl was held: the next plain letters were commands
        // (typing "z" undid). Whoever loses the keyboard forgets modifiers.
        _deckFocus.onFocusChange = { [weak self] focused in
            if !focused { self?._deckChords.reset() }
        }
        if let path = _w.initialPath {
            // Bytes from the browser's picker that crossed the kind switch
            // (a .pptx picked in Writer) arrive by name, not on disk.
            // A browser tab's recovery copy that Writer found at start and handed on opens unsaved.
            if let data = PickedFile.takeRecovered(path) { _open(path, data: data, recovered: true) }
            else if let data = PickedFile.take(path) { _open(path, data: data, handle: PickedFile.takenHandle) }
            else { _open(path) }
        } else if !_w.startBlank, let browser = OfficeHost.browserRecovery {
            // A tab closed with unsaved changes: its copy, under the name it would have saved as.
            if let row = browser.take("pptx") { _open(row.name, data: row.data, recovered: true) }
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
        officeScene.publishToolbar(nil, owner: self)
        officeScene.unregisterFlush(owner: self)
        officeScene.setPictureDrop(nil, owner: self)
        officeScene.setDocumentPath(nil, owner: self)
        deck.removeListeners(owner: self)
        session.controller.removeListeners(owner: self)
        _deckFocus.dispose()
        _notesFocus.dispose()
        _outlineFocus.dispose()
        _search.dispose()
        _thumbScroll.dispose()
        _sorterScroll.dispose()
        if let token = _f5Token { FocusManager.instance.removeKeyInterceptor(token) }
        _endPasteKeys()
        super.dispose()
    }

    private func _wire() {
        session.onBackstage = { [weak self] open in self?.setState { self?._backstage = open ? .home : nil } }
        session.onNew = { [weak self] in self?._newDeck() }
        session.guardWindowClose()
        session.routeFieldChords()
        session.homeForKeys { [weak self] in
            guard let self, self.mounted, self._backstage == nil, self._show == nil, !self._headerFooter else { return nil }
            return self._deckFocus
        }
        session.onFind = { [weak self] replace in self?._openFind(replace: replace) }
        session.onSymbolDialog = { [weak self] in
            guard let self, self._active != nil || self._notesActive else { return }
            self.setState { self._symbolOpen = true }
        }
        // F5 starts the show wherever the keyboard is — in a title being
        // typed, the notes, a field — not only when the deck itself has it
        // (PowerPoint's F5 does not care what you were doing). Taken ahead
        // of the focused node; the deck's own F5 below stays for its Shift
        // and Alt forms.
        if let token = _f5Token { FocusManager.instance.removeKeyInterceptor(token) }
        _f5Token = FocusManager.instance.addKeyInterceptor { [weak self] key in
            guard let self, self.mounted, key.type == .down,
                  KeyChordTracker.named(key.logical) == .function(5),
                  self._backstage == nil, self._show == nil, !self._headerFooter,
                  FocusManager.instance.focusedNode !== self._deckFocus else { return false }
            self._startShow(at: 0)
            return true
        }
        session.onNewKind = { [weak self] kind in
            guard let self else { return }
            if kind == .presentation { self._newDeck() } else { self._w.onSwitch(kind, nil) }
        }
        session.onOpen = { [weak self] in
            guard let self else { return }
            // The browser's picker, not Backstage's directory list: a tab
            // has no directories, only files the user hands over. Where the
            // browser gives a file handle, Save writes back through it.
            if let files = OfficeHost.browserFiles {
                files.open(OfficeFormats.pickable) { [weak self] picked in
                    self?._open(picked.name, data: picked.data, handle: picked.handle)
                }
                return
            }
            #if !os(WASI)
            // A host with its own document browser (the iPad's) takes Open;
            // unsaved edits still get Backstage's prompt first.
            if officeScene.openRequested != nil {
                self.session.replacing { _ = self.officeScene.openRequested?() }
                return
            }
            self.setState { self._backstage = .open }
            #endif
        }
        session.onSave = { [weak self] in self?._save() }
        session.onSaveAs = { [weak self] in
            guard let self else { return }
            // The browser's own save picker where it has one (Chrome, Edge);
            // elsewhere Backstage's name box, and a download.
            if let files = OfficeHost.browserFiles {
                if files.canPickPlace { self._saveAsInBrowser(files) } else { self.setState { self._backstage = .saveAs } }
                return
            }
            #if !os(WASI)
            if let ask = officeScene.exportRequested {
                self._endEditing()
                let name = self.session.path.map { $0.lastPathComponent }
                    ?? self.session.title.deletingPathExtension + ".pptx"
                ask(name, { [weak self] path, finished in
                    guard let self else { finished(false); return }
                    finished((try? Pptx.write(self.deck).write(to: URL(fileURLWithPath: path))) != nil)
                }, true) { _ in }
                return
            }
            self.setState { self._backstage = .saveAs }
            #endif
        }
        session.onExport = { [weak self] ext in self?._export(ext) }
        session.onShare = { [weak self] ext in self?._export(ext, share: true) }
        session.onPrint = { [weak self] in self?._endEditing(); self?.setState { self?._backstage = nil; self?._printOpen = true } }
        session.onShortcuts = { [weak self] in self?.setState { self?._backstage = nil; self?._shortcutsOpen = true } }
        #if os(iOS)
        // OFFICE_DRIVE_EXPORT=pdf (or print): File → Export → PDF (File → Print) a few seconds after the
        // document opens, so a driven run can reach the export picker
        // without a tile tap.
        if let ext = ProcessInfo.processInfo.environment["OFFICE_DRIVE_EXPORT"], !ext.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                if ext == "print" { self?.session.onPrint?() } else { self?.session.onExport?(ext) }
            }
        }
        #endif
        hostDebugQuery = { [weak self] kind in
            // `starling.debug('pdf')`: File → Export → PDF without the clicks —
            // the download is what a script then compares. 'name' and
            // 'status' are how that script knows where it is: the open
            // document's name, and the status bar's message.
            #if os(WASI)
            if kind == "pdf" { self?._export("pdf"); return "exporting" }
            if kind == "controls", let self { return ControlList.text(self.context) }
            if kind == "name" { return self?.session.title }
            if kind == "status" { return self?._status ?? "" }
            #endif
            return nil
        }
        session.onStatus = { [weak self] m in self?._flash(m) }
        // The ribbon's Cut, Copy and Paste act on the selected shapes first.
        session.onShapeCopy = { [weak self] in
            guard let self, self._active == nil, !self._notesActive, self.deck.copyShapes() else { return false }
            self._flash("Copied"); return true
        }
        session.onShapeCut = { [weak self] in
            guard let self, self._active == nil, !self._notesActive else { return false }
            return self.deck.cutShapes()
        }
        session.onShapePaste = { [weak self] in
            guard let self, self._active == nil, !self._notesActive else { return false }
            self._pasteOnSlide(); return true
        }
        session.onShapeSelectAll = { [weak self] in
            guard let self, self._active == nil, !self._notesActive else { return false }
            self.deck.selectShapes(self.deck.currentSlide.shapes); return true
        }
        // Table Layout > Select > Draw Table / Eraser: the deck's own table pen (Table Design > Draw Borders).
        session.onTableTool = { [weak self] tool in
            guard let self else { return }
            let want: DeckController.TableTool = tool == "draw" ? .draw : tool == "erase" ? .erase : .none
            self.deck.tableTool = self.deck.tableTool == want ? .none : want
        }
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
            self._pictureForShapeFill = nil
            self.session.pickingMedia = false
            self._pictureForChange = false
            self._pickPicture()
        }
        session.onInsertMedia = { [weak self] video in
            guard let self else { return }
            self._pictureForBackground = false
            self.session.pickingMedia = true
            self._pickMedia(video: video)
        }
        session.onMoreShapeColor = { [weak self] outline in
            guard let self else { return }
            self.setState { self._shapeColorFor = outline }
        }
        session.onMoreColors = { [weak self] in
            guard let self else { return }
            self.setState { self._colorOpen = true }
        }
        session.onHeaderFooter = { [weak self] in
            guard let self else { return }
            self._endEditing()
            self.setState { self._headerFooter = true }
        }
        session.onSlideSize = { [weak self] size in
            guard let self else { return }
            self._endEditing()
            self.setState { self._slideSizeInitial = size ?? self.deck.slideSize; self._slideSize = true }
        }
        session.onLink = { [weak self] in self?._openLink() }
        // (The caret stays in its cell: the margins go to the cells chosen there.)
        session.onCellMarginsDialog = { [weak self] in
            guard let self, self.session.controller.currentCell != nil else { return }
            self.setState { self._cellMargins = true }
        }
        session.onZoomDialog = { [weak self] in
            guard let self else { return }
            self._endEditing()
            self.setState { self._zoomDialog = true }
        }
        session.onAltText = { [weak self] in
            guard let self, !self.deck.selection.isEmpty else { return }
            self._endEditing()
            self.setState { self._altText = true }
        }
        session.onTextOptions = { [weak self] in
            guard let self, self.deck.selectedTextOptions != nil else { return }
            self._endEditing()
            self.setState { self._textOptions = true }
        }
        session.onToggleAutoSave = { [weak self] in
            guard let self else { return }
            self.setState { self.session.autoSave.toggle() }
            self._flash(self.session.autoSave ? "AutoSave on" : "AutoSave off — a recovery copy is still kept")
        }
        session.onFormatBackground = { [weak self] in
            self?.setState { self?._formatBackground.toggle() }
        }
        session.onFormatShape = { [weak self] in
            self?.setState { self?._formatShape.toggle() }
        }
        session.onSelectionPane = { [weak self] in
            self?.setState { self?._selectionPane.toggle() }
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
        session.onShapeFillPicture = { [weak self] tiled in
            guard let self else { return }
            self._pictureForBackground = false
            self._pictureForShapeFill = tiled
            self._pictureForChange = false
            self._pickPicture()
        }
        session.onChangePicture = { [weak self] in
            guard let self, self.deck.selection.contains(where: { $0.picture != nil }) else { return }
            self._pictureForBackground = false
            self._pictureForShapeFill = nil
            self._pictureForChange = true
            self._pickPicture()
        }
        session.onBackgroundPicture = { [weak self] in
            guard let self else { return }
            self._pictureForBackground = true
            self._pictureForChange = false
            self._pickPicture()
        }
        session.onInsertShape = { [weak self] preset in
            guard let self else { return }
            self._endEditing()
            self.deck.beginInsert(preset)
            self._deckFocus.requestFocus()
        }
        session.onSlidesView = { [weak self] sorter in
            guard let self else { return }
            self._endEditing()
            self.deck.setNotesPageView(false)
            if self._outline { self.deck.endOutlineEdit() }
            self.session.slidesOutline = false
            self.setState { self._sorter = sorter; self._outline = false }
        }
        session.onSlidesOutline = { [weak self] in
            guard let self else { return }
            self._endEditing()
            self.deck.setNotesPageView(false)
            let on = !self._outline
            if on { self._loadOutline() } else { self.deck.endOutlineEdit() }
            self.session.slidesOutline = on
            self.setState { self._outline = on; self._sorter = false }
        }
        session.onSlidesNotesPage = { [weak self] in
            guard let self else { return }
            self._endEditing()
            self.setState { self._sorter = false }
            self.deck.setNotesPageView(true)
        }
        session.onUndo = { [weak self] in self?._undo() }
        session.onRedo = { [weak self] in self?._redo() }
        session.onSlideShow = { [weak self] fromCurrent in
            guard let self else { return }
            self._startShow(at: fromCurrent ? self.deck.current : 0)
        }
        session.onRehearse = { [weak self] in
            guard let self else { return }
            self._startShow(at: self.deck.showOrder().first ?? 0, rehearse: true)
        }
        session.onSetUpShow = { [weak self] in
            guard let self else { return }
            self._endEditing()
            self.setState { self._setUpShow = true }
        }
        session.onSectionName = { [weak self] rename in self?._nameSection(rename: rename) }
        session.onMasterView = { [weak self] open in
            guard let self else { return }
            self._endEditing()
            if open {
                guard (try? self.deck.enterMasterView()) != nil else { return }
                self.setState { self._tab = .slideMaster; self._sorter = false }
            } else {
                _ = try? self.deck.closeMasterView()
                self.setState { self._tab = .home }
            }
        }
        session.onLayoutName = { [weak self] in
            guard let self, let role = self.deck.masterPage else { return }
            self.setState { self._sectionDialog = (role.kind == .master ? "Rename Master" : "Rename Layout", role.name, { [weak self] n in self?.deck.renameMasterPage(n) }) }
        }
        session.onCustomShows = { [weak self] in
            guard let self else { return }
            self._endEditing()
            self.setState { self._customShowsOpen = true }
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
        if controller == nil { _showSelection() }
        if next !== session.controller {
            session.controller.removeListeners(owner: self)
            session.controller = next
            next.addListener({ [weak self] in self?._textChanged() }, owner: self)
        }
        if let theme { session.theme = theme }
        session.summary = _summarize()
        _publishToolbar()
    }

    /// With shapes selected and no caret in them, the ribbon shows and formats all of their text, as PowerPoint's does with a
    /// shape's border solid (S-TX-1): `_scratch` holds their paragraphs, all selected, and hands each Font or Paragraph command
    /// to the deck (one undo step). With nothing selected it is empty and keeps what it is given.
    private func _showSelection() {
        let shapes = deck.selection.filter { $0.text != nil }
        let key = (revision: deck.revision, ids: shapes.map(\.id))
        if let seen = _scratchShows, seen.revision == key.revision, seen.ids == key.ids { return }
        _scratchShows = key
        guard !shapes.isEmpty else {
            _scratch.formatRelay = nil
            if _scratch.document != RichDocument() { _scratch.load(RichDocument()) }
            return
        }
        _scratch.load(RichDocument(paragraphs: shapes.flatMap { $0.text!.document.paragraphs }))
        _scratch.selectAll()
        _scratch.formatRelay = { [weak self] apply in self?.deck.formatSelectedText(apply) }
        if let theme = shapes.first?.textTheme { session.theme = theme }
    }

    /// The keyboard's toolbar: the text being typed in, with undo and redo
    /// reaching the deck as well (the same questions the ribbon asks).
    private func _publishToolbar() {
        guard officeScene.toolbarChanged != nil else { return }
        let s = session.summary
        officeScene.publishToolbar(.init(
            canUndo: s.canUndo, canRedo: s.canRedo,
            bold: s.bold, italic: s.italic, underline: s.underline,
            hasLists: true, list: s.list,
            undo: { [weak self] in self?._undo() }, redo: { [weak self] in self?._redo() },
            toggleBold: { [weak self] in self?.session.controller.toggleBold() },
            toggleItalic: { [weak self] in self?.session.controller.toggleItalic() },
            toggleUnderline: { [weak self] in self?.session.controller.toggleUnderline() },
            toggleList: { [weak self] in self?.session.controller.toggleList($0) },
            // A selected shape (typing in one counts): copy it, remove it, move it in the stack.
            context: deck.selection.isEmpty ? [] : [
                OfficeHost.colorButton(id: "ctx-shape-fill", title: "Shape Fill", symbol: "paintpalette", none: "No Fill") { [weak self] in self?.deck.setFill($0) },
                OfficeHost.colorButton(id: "ctx-shape-outline", title: "Shape Outline", symbol: "square.dashed", none: "No Outline") { [weak self] in self?.deck.setOutline($0) },
                .init(id: "ctx-shape-dup", title: "Duplicate", symbol: "plus.square.on.square") { [weak self] in self?.deck.duplicateSelection() },
                .init(id: "ctx-shape-del", title: "Delete", symbol: "trash") { [weak self] in self?.deck.deleteSelection() },
                .init(id: "ctx-shape-fwd", title: "Bring Forward", symbol: "square.2.layers.3d.top.filled") { [weak self] in self?.deck.arrange(.forward) },
                .init(id: "ctx-shape-back", title: "Send Backward", symbol: "square.2.layers.3d.bottom.filled") { [weak self] in self?.deck.arrange(.backward) },
            ]), owner: self)
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
        // The text left behind keeps its caret and lets its selection go:
        // every text shape's editor stays mounted, and one that was left
        // with a range selected went on painting the highlight with
        // nothing being edited.
        if let left = _active, left !== shape, let text = left.text, text.hasSelection {
            text.selection = RichSelection(caret: text.selection.end)
        }
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
        _endEditing()
        setState { _findOpen = true }
    }

    /// What the shared Find and Replace dialog does in Slides: the whole deck, every text body and the notes.
    private var _findHooks: FindHooks {
        var hooks = FindHooks(
            findNext: { [unowned self] p, _, back in _findNext(p, backwards: back) },
            replace: { [unowned self] p, template, _ in
                // The match the caret is on goes, then on to the next one.
                let c = session.controller
                let replaced = (_active != nil || _notesActive) && c.replaceSelection(p, with: template)
                let next = _findNext(p, backwards: false)
                return replaced ? (next.hasPrefix("No") ? "Replaced. No more matches" : "Replaced") : next
            },
            replaceAll: { [unowned self] p, template, _ in
                _endEditing()
                let n = deck.replaceEverywhere(p, with: template)
                setState {}
                return n == 0 ? "No matches" : "Replaced \(n)"
            })
        hooks.goToLabel = "Go to slide"
        hooks.goToHint = "A slide number, from 1"
        hooks.goTo = { [unowned self] text in
            guard let n = Int(text.trimmingWhitespace()), n >= 1 else { return "Type a slide number" }
            guard n <= deck.slides.count else { return "The deck has \(deck.slides.count) slides" }
            _endEditing()
            deck.select(n - 1)
            setState {}
            return nil
        }
        return hooks
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

    private func _findNext(_ pattern: TextPattern, backwards: Bool) -> String {
        let all = deck.matches(pattern)
        guard !all.isEmpty else { return "No matches" }
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
        return "\((all.firstIndex(of: pick) ?? 0) + 1) of \(all.count)"
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

    /// Type into the current slide's notes (a click there, or F6). `focus`:
    /// give them the keyboard too (a click focuses the editor itself).
    private func _editNotes(focus: Bool = true) {
        guard !_notesActive else { return }
        deck.endTextSession()
        _active = nil
        _paneFocused = false
        _notesActive = true
        deck.selectShapes([])
        deck.beginTextSession()
        _point(at: deck.currentSlide.notes, theme: _notesTheme)
        if focus {
            // By keyboard: ready to add to what is there.
            deck.currentSlide.notes.moveToDocumentEnd(extend: false)
            _notesFocus.requestFocus()
        }
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
        _publishToolbar()
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
            // The width follows the grid only after an edit changed it: a file's frame is kept as read.
            if let id = shape.tableId {
                let grid = shape.text?.document.tableColumns[id]
                if let seen = _gridSeen[shape.id], seen != grid {
                    // Undo back to no grid gives back the width the table had before its first one.
                    if let grid { deck.fitWidth(shape, grid.reduce(0, +) + shape.insets.left + shape.insets.right) }
                    else if let w = _widthBeforeGrid[shape.id] { deck.fitWidth(shape, w) }
                }
                if grid == nil { _widthBeforeGrid[shape.id] = shape.frame.width }
                _gridSeen[shape.id] = .some(grid)
            }
            guard let layout = _cache.layout(shape, pxPerPt: 1) else { continue }
            // (Up to a hundredth of a point: Table Size's 62.7 pt stays 62.7, as PowerPoint shows it.)
            deck.fitHeight(shape, ((layout.totalHeight + shape.insets.top + shape.insets.bottom) * 100 - 1e-6).rounded(.up) / 100)
        }
    }

    /// What each autofit shape was last measured at (text revision, frame):
    /// it is measured again only once one of them changes, so a deck opens
    /// at the scales the file says.
    private var _fitSeen: [Int: (revision: Int, frame: Rect)] = [:]
    /// Each table's grid when last seen (an inner nil: it stated none), so only an edit to the grid moves its frame.
    private var _gridSeen: [Int: [Double]?] = [:]
    /// Each grid-less table's frame width, for an undo that takes its first grid away.
    private var _widthBeforeGrid: [Int: Double] = [:]

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

    /// Each self-sizing box's text revision when last seen.
    private var _growSeen: [Int: Int] = [:]

    /// A box that sizes itself to its text (spAutoFit) takes the height its text needs once its text changes, as
    /// PowerPoint's text boxes grow while you type. A box as a file left it keeps its frame until then.
    private func _growToText() {
        for shape in deck.currentSlide.shapes where DeckController.resizesToText(shape) {
            guard let text = shape.text else { continue }
            guard let seen = _growSeen[shape.id] else { _growSeen[shape.id] = text.revision; continue }
            guard seen != text.revision else { continue }
            _growSeen[shape.id] = text.revision
            if let h = SlideTextCache.fittedHeight(shape) { deck.fitHeight(shape, h) }
        }
    }

    private func _deckChanged() {
        if _outline && !_outlineSyncing && !_outlineFocus.hasFocus { _loadOutline() }
        _fitTables()
        _autofit()
        _growToText()
        // A selected picture opens its tab; leaving it returns Home.
        let picture = deck.selection.contains { $0.picture != nil }
        if picture && !_hadPicture { _tab = .pictureFormat }
        if !picture && _tab == .pictureFormat { _tab = .home }
        _hadPicture = picture
        // Shape Format shows while a shape, placeholder or text box is selected (PowerPoint does not switch to it).
        if !deck.selectionHasShape && _tab == .shapeFormat { _tab = .home }
        // A selected table opens Table Design the same way.
        let table = deck.selectedTableOptions != nil
        if table && !_hadTable { _tab = .tableDesign }
        if !table && _tab == .tableDesign { _tab = .home }
        _hadTable = table
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
            // The keyboard goes back to the deck with it. Left on the
            // editor of a slide no longer shown (New Slide from the
            // ribbon while typing), every shortcut went nowhere until a click.
            _deckFocus.requestFocus()
        }
        if _notesActive, session.controller !== deck.currentSlide.notes {
            _notesActive = false
            _point(at: nil)
        }
        if _active == nil && !_notesActive && session.controller === _scratch { _showSelection() }
        session.dirty = deck.edits != _savedEdits
        session.summary = _summarize()
        _publishToolbar()
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
        #if os(WASI)
        // Never written (no autosave in a tab); never created either —
        // OfficeRecovery.untitled makes its directory, and
        // FileManager.createDirectory(withIntermediateDirectories:) recurses
        // forever on WASI.
        return path.map { $0 + "~" } ?? "/office-recovery/untitled.pptx~"
        #else
        return path.map { $0 + "~" } ?? OfficeRecovery.untitled("pptx")
        #endif
    }

    /// Two seconds after the last change: AutoSave writes the file itself
    /// when it is on and the deck has one; otherwise the recovery copy is
    /// refreshed — as Writer does.
    private func _scheduleAutosave() {
        #if os(WASI)
        // The browser has no files of ours: only the page's recovery copy.
        guard OfficeHost.browserRecovery != nil else { return }
        #endif
        _autosaveGeneration += 1
        let gen = _autosaveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + OfficeHost.autosaveDelay) { [weak self] in
            guard let self, self.mounted, self._autosaveGeneration == gen else { return }
            self._autosaveNow()
        }
    }

    /// The write itself (also what the window's host asks for before it closes the window,
    /// OfficeScene.flushPendingSaves).
    private func _autosaveNow() {
        guard session.dirty, _show == nil else { return }
        // In a browser tab: the page keeps the copy (there is no file to save in place).
        if let browser = OfficeHost.browserRecovery {
            guard _keptEdits != deck.edits, let data = try? Pptx.write(deck) else { return }
            let name = session.path?.lastPathComponent ?? session.title.deletingPathExtension + ".pptx"
            browser.keep("pptx", name.pathExtension.lowercased() == "pptx" ? name : name.deletingPathExtension + ".pptx", data)
            _keptEdits = deck.edits
            return
        }
        #if !os(WASI)
        guard let data = try? Pptx.write(deck) else { return }
        if session.autoSave, !_recovered, let path = session.path,
           path.pathExtension.lowercased() == "pptx" {
            do {
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                officeScene.documentSaved?(path)
                _savedEdits = deck.edits
                try? FileManager.default.removeItem(atPath: _recoveryPath(for: path))
                setState { session.dirty = false }
                return
            } catch {
                _flash("AutoSave could not write: \(error)")
            }
        }
        try? data.write(to: URL(fileURLWithPath: _recoveryPath(for: session.path)), options: .atomic)
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
        _keptEdits = nil
        if let browser = OfficeHost.browserRecovery {
            browser.discard()
            _recovered = false
            return
        }
        try? FileManager.default.removeItem(atPath: _recoveryPath(for: session.path))
        _recovered = false
    }

    // MARK: Deck commands

    private func _newDeck() {
        _browserHandle = nil
        _active = nil
        _point(at: nil)
        _autosaveGeneration += 1
        _keptEdits = nil
        _recovered = false
        deck.newDeck()
        _savedEdits = deck.edits
        session.path = nil
        setState {
            session.dirty = false
            _backstage = nil
        }
    }

    /// Open from the in-app file panel: a file another window has open is shown by bringing that window forward
    /// (one document, one window: two windows on one file would race on its AutoSave and recovery copy).
    private func _openFromPanel(_ path: String) {
        if let browser = OfficeHost.browserRecent {
            // A tab's Recent holds names; the page reads the kept copy back.
            browser.open(path) { [weak self] kept in
                guard let self, self.mounted else { return }
                guard let kept else {
                    self._recent = browser.names()
                    self.setState { self._backstage = nil }
                    self._flash("\(path) is no longer kept in this browser")
                    return
                }
                self._open(path, data: kept.data, handle: kept.handle)
            }
            return
        }
        if let other = OfficeScene.holding(path, besides: officeScene) {
            other.focusWindow()
            _flash("\(path.lastPathComponent) is open in another window")
            return
        }
        _open(path)
    }

    private func _open(_ path: String) {
        let ext = path.pathExtension.lowercased()
        if OfficeFormats.readable.contains(ext) {
            _w.onSwitch(.document, path)
            return
        }
        if DocumentKind.kind(forPath: path) == .workbook {
            _w.onSwitch(.workbook, path)
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
            try _load(recovered ?? Pptx.read(data), as: path, recovered: recovered != nil)
        } catch {
            _flash("Could not open \(path.lastPathComponent): \(error)")
            setState { _backstage = nil }
        }
    }

    /// A file as bytes, from the browser's picker: no recovery copy to
    /// weigh against it, and a .docx goes to Writer with the same bytes.
    /// `handle`: the page's handle on the picked file, which Save then writes back into.
    private func _open(_ name: String, data: Data, recovered: Bool = false, handle: Int? = nil) {
        // What the tab opens goes to the top of Recent (not a recovery copy: the page holds that already).
        if !recovered { _rememberInBrowser(name, data, handle: handle) }
        let kind = DocumentKind.kind(forPath: name)
        if kind != .presentation {
            PickedFile.hand(name, data, handle: handle)
            _w.onSwitch(kind, name)
            return
        }
        do {
            _autosaveGeneration += 1
            try _load(Pptx.read(data), as: name, recovered: recovered)
            _browserHandle = handle
        } catch {
            _flash("Could not open \(name): \(error)")
            setState { _backstage = nil }
        }
    }

    private func _load(_ read: (DeckState, DeckTheme, PptxPackage), as path: String, recovered: Bool) throws {
        let (state, theme, package) = read
        _endEditing()
        // What was measured of the last deck says nothing of this one: shape
        // ids repeat from deck to deck, and a shape found "changed" against
        // the last deck's frame was refitted by us, over the file's scale.
        _cache.reset()
        _fitSeen.removeAll()
        deck.load(state, theme: theme, package: package)
        session.path = path
        _browserHandle = nil
        // A browser recovery copy is the page's row already.
        _keptEdits = recovered && OfficeHost.browserRecovery != nil ? deck.edits : nil
        _recovered = recovered
        _savedEdits = recovered ? deck.edits - 1 : deck.edits
        _lastAutosaveEdits = deck.edits
        // A browser tab's recovery copy is no file the user opened: Recent is left alone.
        _remember(path, recovered: recovered)
        setState {
            session.dirty = recovered
            _backstage = nil
        }
        _flash(recovered ? "Restored unsaved changes to \(path.lastPathComponent) — Save to keep them"
                         : "Opened \(path.lastPathComponent) — \(deck.slides.count) slides")
    }

    // MARK: Slide show

    private func _startShow(at index: Int, presenter: Bool = false, rehearse: Bool = false) {
        _endEditing()
        hostSetFullscreen?(deck.show.kind != .window)
        setState {
            _show = index
            _presenter = presenter
            _rehearsing = rehearse
        }
    }

    private func _endShow() {
        deck.playCustomShow(nil)
        hostSetFullscreen?(false)
        setState { _show = nil }
        _deckFocus.requestFocus()
    }

    // MARK: Saving

    private func _save() {
        if let files = OfficeHost.browserFiles {
            // Back into the file it came from, where the browser gave us its
            // handle; else the browser's save picker; else a download, named
            // after the deck (the browser decides where it goes).
            if let handle = _browserHandle, let path = session.path, path.pathExtension.lowercased() == "pptx" {
                _writeInBrowser(files, handle: handle, name: path.lastPathComponent)
            } else if files.canPickPlace {
                _saveAsInBrowser(files)
            } else {
                _saveTo(session.title.deletingPathExtension + ".pptx")
            }
            return
        }
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
            if let files = OfficeHost.browserFiles {
                // A tab: a download (Save without a save picker, or Backstage's name box).
                files.download(path.lastPathComponent, data)
                _browserSaved(path.lastPathComponent, data, handle: nil, edits: deck.edits)
                return
            }
            // (WASI has no atomic write; a tab always has browserFiles and returned above.)
            #if os(WASI)
            try data.write(to: URL(fileURLWithPath: path))
            #else
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            #endif
            officeScene.documentSaved?(path)
            // Saved: the copy beside the old name (or the untitled one) goes.
            _dropRecovery()
            session.path = path
            _dropRecovery()
            _savedEdits = deck.edits
            _remember(path, recovered: false)
            setState {
                session.dirty = false
                _backstage = nil
            }
            _flash("Saved \(path.lastPathComponent)")
        } catch {
            _flash("Could not save \(path.lastPathComponent): \(plainFailure(error))")
        }
    }

    // MARK: Saving in a browser tab (web-parity 4, as Writer)

    /// Save As through the browser's own picker: a place and a name for the .pptx.
    private func _saveAsInBrowser(_ files: OfficeHost.BrowserFiles) {
        _endEditing()
        let suggested = session.path.map { $0.lastPathComponent.deletingPathExtension + ".pptx" }
            ?? session.title.deletingPathExtension + ".pptx"
        files.pickPlace(suggested, ["pptx"]) { [weak self] place in
            guard let self, self.mounted, let place else { return }
            self._writeInBrowser(files, handle: place.handle, name: place.name)
        }
    }

    private func _writeInBrowser(_ files: OfficeHost.BrowserFiles, handle: Int, name: String) {
        _endEditing()
        let edits = deck.edits
        let data: Data
        do { data = try Pptx.write(deck) } catch {
            _flash("Could not save \(name): \(plainFailure(error))")
            return
        }
        files.write(handle, data) { [weak self] ok in
            guard let self, self.mounted else { return }
            if ok {
                self._browserSaved(name, data, handle: handle, edits: edits)
            } else {
                self._flash("Could not save \(name): the browser did not allow writing to it")
            }
        }
    }

    /// Written or downloaded: the recovery copy goes, Recent gets the bytes, and Save writes back to `handle`.
    /// Edits made while the browser wrote keep the deck unsaved.
    private func _browserSaved(_ name: String, _ data: Data, handle: Int?, edits: Int) {
        _dropRecovery()
        session.path = name
        _browserHandle = handle
        _savedEdits = edits
        _rememberInBrowser(name, data, handle: handle)
        setState {
            session.dirty = deck.edits != edits
            _backstage = nil
        }
        _flash("Saved \(name)")
    }

    /// A deck opened or saved: natively its path goes to the top of Recent; in a tab the list is the page's.
    /// A browser tab's recovery copy is no file the user opened: Recent is left alone.
    private func _remember(_ path: String, recovered: Bool) {
        if let browser = OfficeHost.browserRecent { _recent = browser.names(); return }
        if !(recovered && OfficeHost.browserRecovery != nil) { _recent = OfficeRecent.remember(path, in: _recent) }
    }

    /// A deck opened or saved in a tab: the page keeps its bytes under its name, so Recent can reopen it.
    private func _rememberInBrowser(_ name: String, _ data: Data, handle: Int?) {
        guard let browser = OfficeHost.browserRecent else { return }
        browser.remember(name, data, handle)
        _recent = browser.names()
    }

    /// PDF or a .pptx copy, beside the deck (or in Documents), named after it.
    private func _export(_ ext: String, share: Bool = false) {
        let base = session.path.map { $0.deletingPathExtension } ?? homeDirectory() + "/Documents/" + session.title.deletingPathExtension
        let target = base + "." + ext
        _endEditing()
        #if !os(WASI)
        if let ask = share ? officeScene.shareRequested : officeScene.exportRequested {
            setState { _backstage = nil }
            ask(target.lastPathComponent, { [weak self] path, finished in
                guard let self else { finished(false); return }
                if ext == "pptx" {
                    finished((try? Pptx.write(self.deck).write(to: URL(fileURLWithPath: path))) != nil)
                } else {
                    Task { @MainActor [weak self] in
                        guard let self else { finished(false); return }
                        finished(await SlidesPdf.write(self.deck, cache: self._cache, to: path, title: self.session.title))
                    }
                }
            }, false) { [weak self] picked in
                if let picked { self?._flash("\(share ? "Shared" : "Exported") \(picked)") }
            }
            return
        }
        #endif
        if ext == "pptx" {
            do {
                let data = try Pptx.write(deck)
                #if os(WASI)
                WebFiles.download(data, as: target.lastPathComponent)
                #else
                try data.write(to: URL(fileURLWithPath: target), options: .atomic)
                #endif
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

    /// What the Print dialog asks of the deck: Slides, Notes Pages or
    /// Handouts, for a page range, with the selected slides as a choice.
    var _printHooks: PrintHooks {
        PrintHooks(unit: "Slides", total: max(1, deck.slides.count), current: deck.current + 1,
                   selection: _selectedSlideNumbers(), outputs: ["Slides", "Notes Pages", "Handouts"],
                   hostCanPrint: hostCanPrintPDF, print: { [weak self] pages, output in
                       self?._print(slides: pages, output: output) ?? ""
                   })
    }

    /// The selected slides' numbers (1-based), or nil when only one is.
    private func _selectedSlideNumbers() -> [Int]? {
        let ids = deck.slideSelectionIds
        let n = deck.slides.enumerated().filter { ids.contains($0.element.id) }.map { $0.offset + 1 }
        return n.count > 1 ? n : nil
    }

    /// File → Print: the chosen slides (or their notes pages, or handouts)
    /// as a PDF, handed to the host's print dialog. Returns the status line.
    private func _print(slides: [Int], output: Int) -> String {
        // A host that prints bytes (the browser) gets the PDF itself; one
        // that prints files gets a file in the temporary folder.
        let bytes = hostPrintPDFBytes
        guard bytes != nil || hostPrintPDF != nil else { return "No print dialog on this host" }
        #if os(WASI)
        let path = "/print/" + session.title.deletingPathExtension + ".pdf"
        #else
        let path = NSTemporaryDirectory() + "slides-print-\(ProcessInfo.processInfo.processIdentifier).pdf"
        #endif
        let name = session.title.deletingPathExtension + ".pdf"
        let kind = SlidesPdf.Output(rawValue: output) ?? .slides
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await SlidesPdf.write(self.deck, cache: self._cache, to: path, title: self.session.title,
                                        slides: slides, output: kind, notesTheme: self._notesTheme,
                                        deliver: bytes.map { send in { data in send(data, name) } }) else {
                self._flash("Could not render the deck for printing")
                return
            }
            if bytes == nil, let print = hostPrintPDF { print(path) }
        }
        return "Sent to the print dialog"
    }

    /// Where a picture comes from: Backstage's file list, or in a tab the
    /// browser's picker.
    private func _pickPicture() {
        #if os(WASI)
        WebFiles.open(extensions: ["png", "jpg", "jpeg", "gif", "bmp", "webp"]) { [weak self] picked in
            guard let self, let picked else { return }
            self._insertPicture(picked.name, data: picked.data)
        }
        #else
        // OFFICE_PICK_PICTURE=path: a driver script's stand-in for the system picker (no driver can tap it), on every platform.
        if let stub = ProcessInfo.processInfo.environment["OFFICE_PICK_PICTURE"], !stub.isEmpty { _insertPicture(stub); return }
        if let ask = officeScene.pictureRequested {
            ask { [weak self] path in if let path { self?._insertPicture(path) } }
            return
        }
        setState { _backstage = .insertPicture }
        #endif
    }

    /// Insert → Audio / Video: the file as a clip on the slide, drawn as its
    /// poster frame (the frame itself comes with playback).
    private func _pickMedia(video: Bool) {
        let done: (String, Data) -> Void = { [weak self] name, data in self?._insertMedia(name, data: data) }
        #if os(WASI)
        WebFiles.open(extensions: Array(MediaClip.videoExtensions.union(MediaClip.audioExtensions)).sorted()) { picked in
            if let picked { done(picked.name, picked.data) }
        }
        #else
        if let ask = officeScene.pictureRequested {
            ask { path in
                if let path, let data = FileManager.default.contents(atPath: path) { done(path.lastPathComponent, data) }
            }
            return
        }
        setState { _backstage = .insertPicture }
        #endif
    }

    private func _insertMedia(_ name: String, data: Data) {
        session.pickingMedia = false
        setState { _backstage = nil }
        var clip = MediaClip(data: data, name: name, isVideo: false)
        let ext = clip.fileExtension
        guard MediaClip.videoExtensions.contains(ext) || MediaClip.audioExtensions.contains(ext) else {
            _flash("Not a sound or movie Slides can place: \(name)")
            return
        }
        clip.isVideo = MediaClip.isVideo(extension: ext)
        let (poster, size) = MediaPoster.attachment(video: clip.isVideo, name: "poster.png")
        _endEditing()
        let shape = deck.addMedia(clip, poster: poster, size: size)
        _deckFocus.requestFocus()
        _flash("Inserted \(name)")
        if clip.isVideo { _takePoster(for: shape, clip: clip) }
    }

    /// Swaps the generic poster for the clip's first frame once it is decoded, keeping the width and the frame's centre.
    private func _takePoster(for shape: SlideShape, clip: MediaClip) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let f = MediaPoster.firstFrame(of: clip) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, case .picture = shape.kind else { return }
                let w = shape.frame.width, h = w * Double(f.height) / Double(f.width)
                let cx = shape.frame.left + w / 2, cy = shape.frame.top + shape.frame.height / 2
                self.deck.replacePoster(shape, png: f.png, width: f.width, height: f.height,
                                        frame: Rect.fromLTWH(cx - w / 2, cy - h / 2, w, h))
                self.setState {}
            }
        }
    }

    private func _insertPicture(_ path: String) {
        if session.pickingMedia {
            guard let data = FileManager.default.contents(atPath: path) else {
                session.pickingMedia = false
                setState { _backstage = nil }
                _flash("Could not read \(path.lastPathComponent)")
                return
            }
            _insertMedia(path.lastPathComponent, data: data)
            return
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            setState { _backstage = nil }
            _flash("Could not read \(path.lastPathComponent)")
            return
        }
        _insertPicture(path, data: data)
    }

    private func _insertPicture(_ path: String, data: Data) {
        setState { _backstage = nil }
        let forBackground = _pictureForBackground
        let forShapeFill = _pictureForShapeFill, forChange = _pictureForChange
        _pictureForShapeFill = nil
        _pictureForChange = false
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
                if forChange {
                    self.deck.changePictures(to: image)
                    self._deckFocus.requestFocus()
                    self._flash("Changed to \(path.lastPathComponent)")
                    return
                } else if forBackground {
                    self.deck.setBackground(SlideFill(image: image))
                } else if let tiled = forShapeFill {
                    self.deck.setPictureFill(image, tiled: tiled)
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

    /// A paste with nothing being edited: this deck's shapes, a picture, or nothing (S-ED-1; see SlidesClipboard.swift).
    private func _pasteOnSlide() {
        DeckController.registerClipboardFormats()
        Clipboard.getData(Clipboard.kAll) { [weak self] data in
            DispatchQueue.main.async { self?.deck.pasteOnSlide(data) }
        }
    }

    /// A paste in the thumbnail pane or the sorter: the clipboard's slides (this deck's or another's) after the
    /// picked one; anything else goes onto the slide.
    private func _pasteSlides() {
        _endEditing()
        DeckController.registerClipboardFormats()
        Clipboard.getData(Clipboard.kAll) { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                if !self.deck.pasteSlides(from: data) { self.deck.pasteOnSlide(data) }
            }
        }
    }

    /// The Paste Options button under pasted slides: Use Destination Theme or Keep Source Formatting, by click or
    /// by H and K.
    func _showSlidesPasteOptions(at point: Offset) {
        let deck = self.deck
        guard deck.slidesPasteOptions != nil, let context else { return }
        let m = ContextMenuBuilder()
        for way in SlidePasteWay.slideWays {
            m.item(way.label, enabled: way != deck.slidesPasteOptions) { [weak self] in self?._repasteSlides(way) }
        }
        m.show(_thumbMenu, in: context, at: point)
        _endPasteKeys()
        _pasteKeys = FocusManager.instance.addKeyInterceptor { [weak self] key in
            guard let self else { return false }
            guard self._thumbMenu.isOpen, self.deck.slidesPasteOptions != nil else { self._endPasteKeys(); return false }
            guard let letter = KeyChordTracker.letter(key.logical),
                  let way = SlidePasteWay.slideWays.first(where: { $0.letter == letter }) else { return false }
            if key.type == .down { self._repasteSlides(way) }
            return true
        }
    }

    private func _repasteSlides(_ way: SlidePasteWay) {
        _endPasteKeys()
        if _thumbMenu.isOpen { _thumbMenu.closeFlyout() }
        deck.repasteSlides(way)
    }

    /// Paste Special (Ctrl+Alt+V): reads the whole clipboard, then asks which format to paste.
    private func _openPasteSpecial() {
        _endEditing()
        DeckController.registerClipboardFormats()
        Clipboard.getData(Clipboard.kAll) { [weak self] data in
            DispatchQueue.main.async {
                guard let self, self.mounted else { return }
                let data = data ?? ClipboardData(text: nil)
                self.setState { self._pasteSpecialData = data }
            }
        }
    }

    /// The Paste Options button's menu: the last paste made again another way, in one undo step. While it is open
    /// K, U and T pick, as PowerPoint's underlined letters do.
    func _showPasteOptions(at point: Offset) {
        let deck = self.deck
        guard deck.slidePasteOptions != nil, let context else { return }
        let m = ContextMenuBuilder()
        for way in SlidePasteWay.allCases {
            m.item(way.label, enabled: deck.canRepaste(way)) { [weak self] in self?._repaste(way) }
        }
        m.show(_thumbMenu, in: context, at: point)
        _endPasteKeys()
        _pasteKeys = FocusManager.instance.addKeyInterceptor { [weak self] key in
            guard let self else { return false }
            guard self._thumbMenu.isOpen, self.deck.slidePasteOptions != nil else { self._endPasteKeys(); return false }
            guard let letter = KeyChordTracker.letter(key.logical),
                  let way = SlidePasteWay.allCases.first(where: { $0.letter == letter }) else { return false }
            if key.type == .down, self.deck.canRepaste(way) { self._repaste(way) }
            return true
        }
    }

    private func _repaste(_ way: SlidePasteWay) {
        _endPasteKeys()
        if _thumbMenu.isOpen { _thumbMenu.closeFlyout() }
        deck.repaste(way)
    }

    private func _endPasteKeys() {
        if let k = _pasteKeys { FocusManager.instance.removeKeyInterceptor(k); _pasteKeys = nil }
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
            case .delete, .backspace where deck.slides.count > 1: deck.deleteSelectedSlides()
            default: break
            }
            if [.left, .up, .right, .down, .enter, .delete, .backspace].contains(named) { return true }
        }
        if _deckChords.primary || named == .escape {
            if _shortcut(key, _deckChords.modifiers) { return true }
        }
        // Function keys first: they mean the same with shapes selected.
        // F5 plays from the beginning, ⇧F5 from here, ⌥F5 in presenter
        // view (PowerPoint's keys).
        if named == .function(5) {
            _startShow(at: _deckChords.shift || _deckChords.alt ? deck.current : 0, presenter: _deckChords.alt)
            return true
        }
        // F6 moves between the areas as PowerPoint's does — thumbnails, the
        // slide, the notes — and ⇧F6 back; Esc leaves the notes like any text.
        if named == .function(6) {
            if _deckChords.shift {
                setState { _paneFocused = true }
            } else if _paneFocused {
                setState { _paneFocused = false }
            } else {
                _editNotes()
            }
            return true
        }
        // With shapes selected, keys act on them.
        if !deck.selection.isEmpty && !_paneFocused {
            // Ctrl nudges by a hair, Shift by a lot; Alt+Left/Right turns by 15°.
            let step = _deckChords.primary ? 0.5 : _deckChords.shift ? 12.0 : 2.0
            switch named {
            case .left where _deckChords.alt: deck.rotateSelection(by: -15)
            case .right where _deckChords.alt: deck.rotateSelection(by: 15)
            case .left: deck.nudgeSelection(dx: -step, dy: 0)
            case .right: deck.nudgeSelection(dx: step, dy: 0)
            case .up: deck.nudgeSelection(dx: 0, dy: -step)
            case .down: deck.nudgeSelection(dx: 0, dy: step)
            case .delete, .backspace: deck.deleteSelection()
            // Crop mode ends on Esc or Enter, the crop kept, the picture still selected.
            case .escape where deck.cropping != nil, .enter where deck.cropping != nil: deck.endCrop()
            case .escape: deck.selectShapes([])
            case .tab: _cycleSelection(back: _deckChords.shift)
            case .enter:
                guard deck.selection.count == 1, let shape = deck.selection.first, shape.text != nil else { return false }
                _editAtEnd(shape)
            default: return false
            }
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
            deck.deleteSelectedSlides()
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

    func _shortcut(_ key: KeyData, _ mods: KeyModifiers) -> Bool {
        let named = KeyChordTracker.named(key.logical)
        let typing = _active != nil || _notesActive
        // Alt+F10 shows or hides the Selection Pane (PowerPoint).
        if named == .function(10), mods.contains(.alt) {
            setState { _selectionPane.toggle() }
            return true
        }
        // ⌘⇧↩ plays from the beginning, ⌘↩ from here (PowerPoint for Mac).
        if named == .enter, mods.contains(.primary) {
            _startShow(at: mods.contains(.shift) ? 0 : deck.current)
            return true
        }
        if named == .escape {
            // (Esc is Cancel in the Header and Footer dialog: it stayed
            // up — seen on screen 2026-10-13.)
            if _headerFooter { setState { _headerFooter = false }; return true }
            if _slideSize { setState { _slideSize = false }; return true }
            if _altText { setState { _altText = false }; return true }
            if _zoomDialog { setState { _zoomDialog = false }; return true }
            if _cellMargins { setState { _cellMargins = false }; return true }
            if _linkOpen { setState { _linkOpen = false }; return true }
            if _textOptions { setState { _textOptions = false }; return true }
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
        if key.logical == 0x2F, mods.contains(.primary) { session.onShortcuts?(); return true }   // ⌘/ the shortcut list
        // Ctrl+Alt+V: Paste Special (the letter chords below leave Alt chords alone).
        if mods.contains(.primary), mods.contains(.alt), !typing, KeyChordTracker.letter(key.logical) == "v" {
            _openPasteSpecial(); return true
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
        case "n": session.replacing { [weak self] in self?._newDeck() }
        case "o": session.onOpen?()
        case "p": session.onPrint?()
        case "s" where mods.contains(.shift): session.onSaveAs?()
        case "s": session.onSave?()
        case "a" where !typing && !shapes && (_paneFocused || _sorter): deck.selectAllSlides()
        case "a" where !typing: deck.selectShapes(deck.currentSlide.shapes)
        case "c" where !typing && !shapes && (_paneFocused || _sorter): deck.copySlides(); _flash("Copied")
        case "x" where !typing && !shapes && (_paneFocused || _sorter): deck.cutSlides()
        case "v" where !typing && !shapes && (_paneFocused || _sorter): _pasteSlides()
        case "c" where shapes: deck.copyShapes(); _flash("Copied")
        case "x" where shapes: deck.cutShapes()
        case "v" where !typing: _pasteOnSlide()
        case "g" where shapes && !typing && mods.contains(.shift): deck.ungroupSelection()
        case "g" where shapes && !typing:
            if let why = deck.groupRefusal { _flash(why) } else { deck.groupSelection() }
        case "d" where shapes: deck.duplicateSelection()
        case "d" where !typing: deck.duplicateSelectedSlides()
        case "m" where !mods.contains(.shift) && !mods.contains(.alt): _endEditing(); deck.addSlide()
        case "k" where !mods.contains(.shift): _openLink()
        case "f": _openFind(replace: false)
        case "h": _openFind(replace: true)
        // A shape selected with no caret in it: all of its text (S-TX-1; while typing the editor takes these keys).
        case "b" where shapes: c.toggleBold()
        case "i" where shapes: c.toggleItalic()
        case "u" where shapes: c.toggleUnderline()
        case "e": c.setAlignment(.center)
        case "l": c.setAlignment(.left)
        case "r": c.setAlignment(.right)
        case "j": c.setAlignment(.justify)
        default: return false
        }
        return true
    }

    // MARK: Links

    /// Insert Hyperlink (Ctrl+K, Insert > Link): on the selected text while one is edited, else on the selected shapes.
    private func _openLink() {
        let typing = _active != nil || _notesActive
        guard typing || !deck.selection.isEmpty else { _flash("Select text or a shape to link"); return }
        setState { _linkOpen = true }
    }

    private var _linkHooks: HyperlinkHooks {
        let typing = _active != nil || _notesActive
        let c = session.controller
        let targets = deck.slideLinkTargets()
        let now = typing ? (c.currentLink, c.currentLinkTip) : deck.selectedShapeLink
        let isJump = now.0?.hasPrefix("slide:") == true || now.0?.hasPrefix("action:") == true
        var h = HyperlinkHooks(apply: { [weak self] addr, place, text, tip in
            guard let self else { return "" }
            let link = place.map { "slide:" + $0 } ?? addr
            if link.isEmpty { return "Type an address or pick a slide" }
            if typing {
                guard self.session.controller.applyHyperlink(address: link, text: text, tip: tip) else { return "Nothing to link" }
            } else if !self.deck.setShapeLink(link, tip: tip) { return "Select text or a shape" }
            self._flash("Linked")
            return ""
        })
        h.placesLabel = "Place in this document"
        h.places = targets.map { HyperlinkPlace(id: $0.key, title: $0.title, kind: "Slide") }
        h.hasDisplayText = typing
        h.address = isJump ? "" : (now.0 ?? "")
        h.displayText = typing ? c.selectedText : ""
        h.tip = now.1 ?? ""
        h.canRemove = now.0 != nil
        h.remove = { [weak self] in
            guard let self else { return }
            if typing { self.session.controller.setLink(nil) } else { self.deck.setShapeLink(nil, tip: nil) }
        }
        return h
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
            }),
            Ribbon(session: session, tab: _tab, collapsed: _ribbonCollapsed,
                   onTab: { [weak self] t in self?.setState { self?._tab = t } },
                   onCollapse: { [weak self] in self?.setState { self?._ribbonCollapsed.toggle() } }),
        ]
        var work: [Widget] = [Expanded(child: KeyboardPage(focus: { [weak self] in self?._deckFocus.requestFocus() }, child: SlideCanvas(
            key: _canvasKey,
            deck: deck, cache: _cache, active: _active,
            onEdit: { [weak self] shape in self?._activate(shape) },
            onShortcut: { [weak self] key, mods in self?._shortcut(key, mods) ?? false },
            modifiers: { [weak self] in self?._deckChords.modifiers ?? [] },
            spellChecker: session.checkSpelling ? _spelling : nil,
            animationBadges: _tab == .animations || _animationPane,
            onContextMenu: { [weak self] at, shape in self?._showSlideMenu(at: at, on: shape) },
            onPasteOptions: { [weak self] at in self?._showPasteOptions(at: at) })))]
        if _showNotes { work.append(_notesPane(fluent)) }
        if deck.notesPageView && !_sorter {
            work = [Expanded(child: _notesPageView(fluent))]
        }
        if _sorter {
            column.append(Expanded(child: _sorterView(fluent)))
        } else {
            var row: [Widget] = _narrow && !_narrowRail ? [] : [_outline ? _outlinePane(fluent) : _thumbnailPane(fluent)]
            row.append(Expanded(child: Column(crossAxisAlignment: .stretch, children: work)))
            var panes: [Widget] = []
            if _animationPane {
                panes.append(AnimationPane(deck: deck, onClose: { [weak self] in self?.setState { self?._animationPane = false } }))
            }
            if _selectionPane {
                panes.append(SelectionPane(deck: deck, modifiers: { [weak self] in self?._deckChords.modifiers ?? [] },
                                           onClose: { [weak self] in self?.setState { self?._selectionPane = false } }))
            }
            if _formatBackground {
                panes.append(FormatBackgroundPane(deck: deck, onPicture: { [weak self] in self?.session.onBackgroundPicture?() },
                                                  onClose: { [weak self] in self?.setState { self?._formatBackground = false } }))
            }
            if _formatShape {
                panes.append(FormatShapePane(deck: deck, onClose: { [weak self] in self?.setState { self?._formatShape = false } }))
            }
            if _chartData, let chart = deck.selectedChart {
                panes.append(ChartDataPane(key: ValueKey("chart data \(chart.id)"), deck: deck, shape: chart,
                                           onClose: { [weak self] in self?.setState { self?._chartData = false } },
                                           onFieldFocus: { [weak self] on in
                                               self?.session.fieldUndo = on ? { [weak self] redo in redo ? self?._redo() : self?._undo() } : nil
                                           }))
            }
            // The newest pane is a bottom sheet in a narrow window, a slide-over on a touch device, else docked beside the slide.
            column.append(Expanded(child: PaneArrangement.arrange(
                style: PaneArrangement.style(narrow: _narrow, touch: PaneArrangement.isTouchDevice), fluent: fluent,
                document: Expanded(child: Row(crossAxisAlignment: .stretch, children: row)), docked: Array(panes.dropLast()), newest: panes.last)))
        }
        column.append(_statusBar(fluent))

        let window = SizeReporter(onSize: { [weak self] size in
            guard let self, self.mounted, (size.width < Self.narrowBelow) != self._narrow else { return }
            self.setState { self._narrow = size.width < Self.narrowBelow }
        }, child: ColoredBox(color: fluent.scaffoldBackgroundColor,
                             child: Column(crossAxisAlignment: .stretch, children: column)))
        if _printOpen {
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: PrintDialog(
                    hooks: _printHooks, onClose: { [weak self] in self?.setState { self?._printOpen = false } })),
            ])
        }
        if _shortcutsOpen {
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ShortcutListDialog(
                    table: ShortcutTable.slides, onClose: { [weak self] in self?.setState { self?._shortcutsOpen = false } })),
            ])
        }
        if _findOpen {
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: FindReplaceDialog(
                    initialQuery: _findQuery.text, hooks: _findHooks,
                    onClose: { [weak self] in self?.setState { self?._findOpen = false } })),
            ])
        }
        if _symbolOpen {
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SymbolPicker(
                    hooks: SymbolHooks(
                        fonts: ["(current font)"] + OfficeFonts.families(including: session.controller.currentCharStyle.fontFamily ?? OfficeFonts.defaultFamily),
                        insert: { [weak self] text, font in self?.session.controller.insertSymbol(text, font: font) }),
                    onClose: { [weak self] in self?.setState { self?._symbolOpen = false } })),
            ])
        }
        if let start = _show {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SlideShowView(
                    deck: deck, images: _cache, start: start, presenter: _presenter, rehearse: _rehearsing,
                    onEnd: { [weak self] in self?._endShow() })),
            ])
        }
        if _textOptions, deck.selectedTextOptions == nil { _textOptions = false }
        if _textOptions, let opts = deck.selectedTextOptions {
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: TextOptionsDialog(
                    initial: opts,
                    onApply: { [weak self] o in
                        self?.deck.setTextOptions(o)
                        self?.setState { self?._textOptions = false }
                    },
                    onCancel: { [weak self] in self?.setState { self?._textOptions = false } })),
            ])
        }
        if _linkOpen {
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: HyperlinkDialog(
                    hooks: _linkHooks,
                    onClose: { [weak self] in self?.setState { self?._linkOpen = false } })),
            ])
        }
        if _cellMargins {
            let c = session.controller
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: CellMarginsDialog(
                    margins: c.currentCell?.padding ?? EdgeInsets(left: 7.2, top: 3.6, right: 7.2, bottom: 3.6),
                    onApply: { [weak self] m in
                        c.setCellMargins(top: m.top, left: m.left, bottom: m.bottom, right: m.right)
                        self?.setState { self?._cellMargins = false }
                    },
                    onCancel: { [weak self] in self?.setState { self?._cellMargins = false } })),
            ])
        }
        if _zoomDialog {
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ZoomDialog(
                    percent: deck.viewPercent, fit: deck.viewIsFit,
                    onApply: { [weak self] percent in
                        if let percent { self?.deck.setViewZoom(percent: Double(percent)) } else { self?.deck.fitView() }
                        self?.setState { self?._zoomDialog = false }
                    },
                    onCancel: { [weak self] in self?.setState { self?._zoomDialog = false } })),
            ])
        }
        if _altText {
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: AltTextDialog(
                    initial: deck.selectedAltText ?? "", title: deck.selectedAltTitle ?? "",
                    onApply: { [weak self] text, title in
                        self?.deck.setAltText(text, title: title)
                        self?.setState { self?._altText = false }
                    },
                    onCancel: { [weak self] in self?.setState { self?._altText = false } })),
            ])
        }
        if _slideSize {
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SlideSizeDialog(
                    size: _slideSizeInitial,
                    onApply: { [weak self] size, scaling in
                        self?.deck.setSlideSize(size, scaling: scaling)
                        self?.setState { self?._slideSize = false }
                    },
                    onCancel: { [weak self] in self?.setState { self?._slideSize = false } })),
            ])
        }
        if _setUpShow {
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SetUpShowDialog(
                    initial: deck.show, slideCount: deck.slides.count, shows: deck.customShows,
                    onOK: { [weak self] s in
                        self?.deck.setShow(s)
                        self?.setState { self?._setUpShow = false }
                    },
                    onCancel: { [weak self] in self?.setState { self?._setUpShow = false } })),
            ])
        }
        if let data = _pasteSpecialData {
            let ways = SlidePasteWay.specialWays.filter { deck.canPaste(data, way: $0) }
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: WriterPasteSpecialDialog(
                    source: WriterPasteSpecialDialog.sourceLine(data.text), labels: ways.map(\.formatLabel),
                    emptyNote: "The clipboard holds nothing Slides can paste.",
                    onPick: { [weak self] i in
                        self?.setState { self?._pasteSpecialData = nil }
                        self?.deck.paste(data, way: ways[i])
                        self?._deckFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._pasteSpecialData = nil }
                        self?._deckFocus.requestFocus()
                    })),
            ])
        }
        if let d = _sectionDialog {
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SectionNameDialog(
                    title: d.title, initial: d.initial,
                    onOK: { [weak self] n in d.apply(n); self?.setState { self?._sectionDialog = nil } },
                    onCancel: { [weak self] in self?.setState { self?._sectionDialog = nil } })),
            ])
        }
        if _customShowsOpen {
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: CustomShowsDialog(
                    shows: deck.customShows, slides: deck.slides.map { (id: $0.id, title: $0.titleText) },
                    onClose: { [weak self] shows in
                        self?.deck.setCustomShows(shows)
                        self?.setState { self?._customShowsOpen = false }
                    },
                    onPlay: { [weak self] shows, id in
                        guard let self else { return }
                        self.deck.setCustomShows(shows)
                        self.deck.playCustomShow(id)
                        self.setState { self._customShowsOpen = false }
                        self._startShow(at: self.deck.showOrder().first ?? 0)
                    })),
            ])
        }
        if _headerFooter {
            // (The window behind takes no clicks while the dialog is up:
            // its own scrim did not keep them from the slide, and a
            // click beside the dialog selected the shape under it —
            // seen on screen 2026-10-13.)
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: HeaderFooterDialog(
                    initial: deck.headerFooter(of: deck.currentSlide),
                    onApply: { [weak self] hf, all in
                        self?.deck.applyHeaderFooter(hf, toAll: all)
                        self?.setState { self?._headerFooter = false }
                    },
                    onCancel: { [weak self] in self?.setState { self?._headerFooter = false } })),
            ])
        }
        if let outline = _shapeColorFor {
            let now = deck.selection.first.flatMap { outline ? $0.outline : $0.fill }
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: CustomColorDialog(
                    initial: now.map { UInt32(truncatingIfNeeded: $0.value) & 0xFFFFFF } ?? 0,
                    onOK: { [weak self] rgb in
                        self?.deck.applyShapeColor(.rgb(rgb), outline: outline)
                        self?.setState { self?._shapeColorFor = nil }
                    },
                    onCancel: { [weak self] in self?.setState { self?._shapeColorFor = nil } })),
            ])
        }
        if _colorOpen {
            let now = session.controller.currentCharStyle.color
            return Stack(children: [
                IgnorePointer(ignoring: true, child: window),
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: CustomColorDialog(
                    initial: now.map { UInt32(truncatingIfNeeded: $0.value) & 0xFFFFFF } ?? 0,
                    onOK: { [weak self] rgb in
                        self?.session.controller.setTextColor(Color(Int64(0xFF00_0000 | rgb)))
                        self?.setState { self?._colorOpen = false }
                    },
                    onCancel: { [weak self] in self?.setState { self?._colorOpen = false } })),
            ])
        }
        guard let page = _backstage else { return window }
        return Stack(children: [
            window,
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Backstage(
                session: session, page: page, recent: _recent, notice: _status,
                onPage: { [weak self] p in self?.setState { self?._backstage = p } },
                onClose: { [weak self] in self?.setState { self?._backstage = nil } },
                onOpenPath: { [weak self] path in self?._openFromPanel(path) },
                onSavePath: { [weak self] path in self?._saveTo(path) },
                onPicturePath: { [weak self] path in self?._insertPicture(path) }, scene: officeScene)),
        ])
    }

    private let _canvasKey = GlobalKey<State<StatefulWidget>>()

    // MARK: Thumbnails

    private func _thumbnailPane(_ fluent: FluentThemeData) -> Widget {
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        let thumbW = 168.0
        let thumbH = (thumbW * deck.slideSize.height / deck.slideSize.width).rounded()
        // A row: the frame (5 for its border and padding), an insertion
        // line above and below (3 each), 3 of padding each side.
        _revealThumbnail(itemHeight: thumbH + 17)
        var items: [Widget] = []
        let picked = Set(deck.selectedSlides)
        func makeItem(_ i: Int, _ slide: Slide) {
            let current = picked.contains(i)
            let number = Text("\(i + 1)", style: fluent.typography.caption?.copyWith(
                color: slide.hidden ? fluent.resources.textFillColorDisabled : fluent.resources.textFillColorPrimary))
            let frame = DecoratedBox(
                decoration: BoxDecoration(border: Border.all(
                    color: current ? accent : fluent.resources.controlStrokeColorDefault,
                    width: current ? 2.5 : 1)),
                child: Padding(padding: EdgeInsets(all: current ? 1 : 2.5), child: SizedBox(
                    width: thumbW, height: thumbH,
                    // Clipped to the thumbnail: a picture reaching past the
                    // slide's edge was painted over the next thumbnail and
                    // out of the pane.
                    child: ClipRect(child: _dimmedIfHidden(slide, wash: fluent.resources.solidBackgroundFillColorBase,
                                                           child: CustomPaint(
                        painter: SlidePainter(slide: slide, theme: deck.theme, slideSize: deck.slideSize,
                                              revision: deck.revision, cache: _cache),
                        child: SizedBox(expand: ())))))))
            // The insertion line while a thumbnail is dragged over this slot.
            let dropHere = _thumbDrag.map { $0.moved && $0.to == i && $0.to != $0.from } ?? false
            let dropAbove = dropHere && (_thumbDrag!.to < _thumbDrag!.from)
            let line = SizedBox(width: thumbW, height: 3, child: ColoredBox(
                color: dropHere ? accent : Color(0x00000000), child: SizedBox(expand: ())))
            // A reader hears "Slide 3, selected", not the bare number drawn beside the picture.
            let activate: () -> Void = { [weak self] in self?.deck.selectSlide(i); self?._deckFocus.requestFocus() }
            items.append(KeyboardRow(label: "Slide \(i + 1)", activate: activate, child: Semantics(
                label: "Slide \(i + 1)", selected: current, onTap: activate, excludeSemantics: true, child: Listener(
                key: ValueKey("slide.thumb.\(i)"),
                onPointerDown: { [weak self] e in
                    guard let self, let context = self.context else { return }
                    self._thumbDown(i, e, context: context)
                },
                onPointerMove: { [weak self] e in
                    self?._thumbTouch.moved(e.pointer, e.position)
                    self?._thumbMove(e.position, itemHeight: thumbH + 18)
                },
                onPointerUp: { [weak self] e in
                    self?._thumbTouch.up(e.pointer)
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
                        ] + (deck.lastPastedSlide == i ? [_slidesPasteButton(fluent, width: thumbW)] : [])),
                    ]))))))
        }
        if deck.sections.isEmpty {
            for (i, slide) in deck.slides.enumerated() { makeItem(i, slide) }
        } else {
            for (si, sec) in deck.sections.enumerated() {
                let members = deck.slides(inSection: si)
                items.append(_sectionHeader(fluent, si, count: members.count, width: thumbW + 16))
                if !sec.collapsed { for i in members { makeItem(i, deck.slides[i]) } }
            }
        }
        return KeyboardPage(name: "Slide thumbnails", region: "thumbnails", focus: { [weak self] in
            self?._deckFocus.requestFocus(); self?.setState { self?._paneFocused = true }
        }, child: SizedBox(width: thumbW + 46, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.solidBackgroundFillColorBase,
                border: Border(right: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: SingleChildScrollView(controller: _thumbScroll, child: Padding(
                padding: EdgeInsets(left: 0, top: 6, right: 0, bottom: 12),
                child: KeyboardRegion(name: "thumbnails", child: Column(crossAxisAlignment: .start, children: items)))))))
    }

    /// The Paste Options button under the last pasted slide, at its right, as PowerPoint puts it.
    private func _slidesPasteButton(_ fluent: FluentThemeData, width: Double) -> Widget {
        let ink = fluent.resources.textFillColorPrimary
        return SizedBox(width: width, height: 22, child: Align(alignment: Alignment.topRight, child: DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                      border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1),
                                      borderRadius: BorderRadius.circular(3)),
            child: Builder { [weak self] context in
                FlatButton(child: Icon(FluentSystemIcons.paste, size: 14, color: ink), tip: "Paste Options", width: 30, height: 20,
                           action: {
                    guard let self, let box = context.findRenderObject() as? RenderBox else { return }
                    self._showSlidesPasteOptions(at: box.localToGlobal(Offset(0, 20)))
                })
            })))
    }

    /// The header row of a section in the thumbnail rail and the Slide Sorter: a fold arrow, the name and the slide count. Right-click for the section's commands.
    private func _sectionHeader(_ fluent: FluentThemeData, _ si: Int, count: Int, width: Double) -> Widget {
        let sec = deck.sections[si]
        return Listener(
            key: ValueKey("section.header.\(si)"),
            onPointerDown: { [weak self] e in
                guard let self, let context = self.context else { return }
                if e.buttons == 2 { self._showSectionMenu(si, at: e.position, context: context) }
            },
            behavior: .opaque,
            child: Padding(padding: EdgeInsets(left: 6, top: 4, right: 6, bottom: 2), child: SizedBox(width: width, height: 26, child: Row(
                crossAxisAlignment: .center, children: [
                    FlatButton(child: Icon(sec.collapsed ? FluentSystemIcons.chevronRight : FluentSystemIcons.chevronDown, size: 12,
                                           color: fluent.resources.textFillColorPrimary),
                               tip: sec.collapsed ? "Expand section" : "Collapse section", width: 22, height: 22) { [weak self] in
                        self?.deck.setSectionCollapsed(si, !sec.collapsed)
                    },
                    Expanded(child: Text("\(sec.name) (\(count))", style: fluent.typography.bodyStrong, overflow: .ellipsis, maxLines: 1)),
                ]))))
    }

    private func _showSectionMenu(_ si: Int, at point: Offset, context: any BuildContext) {
        let m = ContextMenuBuilder()
        m.item("Rename Section") { [weak self] in self?._nameSection(rename: true, section: si) }
        m.item("Remove Section") { [weak self] in self?.deck.removeSection(si) }
        m.item("Remove Section & Slides", enabled: deck.slides(inSection: si).count < deck.slides.count) { [weak self] in self?.deck.removeSectionAndSlides(si) }
        m.item("Remove All Sections") { [weak self] in self?.deck.removeAllSections() }
        m.separator()
        m.item("Move Section Up", enabled: si > 0) { [weak self] in self?.deck.moveSection(si, by: -1) }
        m.item("Move Section Down", enabled: si < deck.sections.count - 1) { [weak self] in self?.deck.moveSection(si, by: 1) }
        m.separator()
        m.item("Collapse All") { [weak self] in self?.deck.setAllSectionsCollapsed(true) }
        m.item("Expand All") { [weak self] in self?.deck.setAllSectionsCollapsed(false) }
        m.show(_thumbMenu, in: context, at: point)
    }

    /// Open the name box for Add Section (at the current slide) or Rename Section.
    private func _nameSection(rename: Bool, section: Int? = nil) {
        let si = section ?? deck.sectionIndex(ofSlide: deck.current)
        if rename {
            guard let si, deck.sections.indices.contains(si) else { return }
            setState { self._sectionDialog = ("Rename Section", self.deck.sections[si].name, { [weak self] n in self?.deck.renameSection(si, to: n) }) }
        } else {
            let at = deck.current
            setState { self._sectionDialog = ("Add Section", "Untitled Section", { [weak self] n in self?.deck.addSection(at: at, name: n.isEmpty ? "Untitled Section" : n) }) }
        }
    }

    /// A hidden slide's thumbnail, faded: the slide as it is with a wash of
    /// the pane's colour over it. (It was an `Opacity` around the painter,
    /// and on Windows that drew nothing at all — a hidden slide's thumbnail
    /// was an empty box. Why the opacity layer comes out empty there is not
    /// known; the wash needs no layer.)
    private func _dimmedIfHidden(_ slide: Slide, wash: Color, child: Widget) -> Widget {
        guard slide.hidden else { return child }
        return Stack(children: [
            child,
            Positioned(left: 0, top: 0, right: 0, bottom: 0,
                       child: IgnorePointer(child: ColoredBox(color: wash.withOpacity(0.55), child: SizedBox(expand: ())))),
        ])
    }

    /// Scroll the thumbnail pane so the current slide's thumbnail is in
    /// view — after the frame that laid the pane out, when its extent is
    /// known. `itemHeight` is one thumbnail's row.
    private func _revealThumbnail(itemHeight: Double) {
        let current = deck.current
        FrameCallbackScheduler.shared.addPostFrameCallback { [weak self] _ in
            guard let self, self._thumbScroll.hasClients else { return }
            let pos = self._thumbScroll.position
            // A pane mounted afresh starts at the top whatever was shown
            // before, and that happens whenever something is laid over the
            // window (a show, Backstage, a dialog: the window moves into a
            // Stack and its subtree remounts). So the scroll position's
            // identity counts as well as the slide's index.
            let mounted = ObjectIdentifier(pos)
            guard current != self._thumbShown || mounted != self._thumbPosition else { return }
            let top = 6 + self._railOffset(of: current, itemHeight: itemHeight)
            let bottom = top + itemHeight
            var target = pos.pixels
            if top < target { target = top - 6 }
            else if bottom > target + pos.viewportDimension { target = bottom - pos.viewportDimension + 6 }
            // Should a pane just mounted not have its extent yet, scrolling
            // would clamp to the top and count as done: look again next
            // frame rather than settle for that.
            let content = 18 + self._railOffset(of: self.deck.slides.count, itemHeight: itemHeight)
            if pos.maxScrollExtent <= 0, content > pos.viewportDimension, self._thumbRetries < 5 {
                self._thumbRetries += 1
                self.setState {}
                return
            }
            self._thumbRetries = 0
            self._thumbShown = current
            self._thumbPosition = mounted
            target = min(max(0, target), pos.maxScrollExtent)
            if abs(target - pos.pixels) > 0.5 { self._thumbScroll.jumpTo(target) }
        }
    }

    private func _sorterDown(_ index: Int, _ e: PointerDownEvent, context: any BuildContext) {
        if _thumbTouch.down(e, fire: { [weak self] p in self?._thumbMenuFromTouch(index, at: p) }) { return }
        if e.buttons & kSecondaryMouseButton != 0 {
            if !deck.selectedSlides.contains(index) { _select(index) }
            _paneFocused = true
            _showThumbMenu(at: e.position, context: context)
            return
        }
        // Dragging an unpicked tile picks it first; a picked group drags together.
        if !deck.selectedSlides.contains(index), !_deckChords.shift, !_deckChords.primary { deck.selectSlide(index) }
        _sorterDrag = (index, e.position.dx, e.position.dy, index, false)
    }

    private func _sorterMove(_ position: Offset, tile: (w: Double, h: Double)) {
        guard var drag = _sorterDrag else { return }
        let dx = position.dx - drag.startX, dy = position.dy - drag.startY
        if !drag.moved && abs(dx) < 6 && abs(dy) < 6 { return }
        drag.moved = true
        let steps = Int((dx / tile.w).rounded()) + _sorterPerRow * Int((dy / tile.h).rounded())
        let to = max(0, min(deck.slides.count - 1, drag.from + steps))
        let changed = to != drag.to || !(_sorterDrag?.moved ?? false)
        drag.to = to
        _sorterDrag = drag
        if changed { setState {} }
    }

    private func _sorterUp() {
        guard let drag = _sorterDrag else { return }
        _sorterDrag = nil
        if drag.moved, drag.to != drag.from {
            let picked = deck.selectedSlides
            if picked.count > 1 { deck.moveSelectedSlides(to: picked[0] + (drag.to - drag.from)) }
            else { deck.moveSlide(drag.from, to: drag.to) }
        } else { setState {} }
    }

    private func _thumbDown(_ index: Int, _ e: PointerDownEvent, context: any BuildContext) {
        if _thumbTouch.down(e, fire: { [weak self] p in self?._thumbMenuFromTouch(index, at: p) }) { return }
        if e.buttons & kSecondaryMouseButton != 0 {
            // A right-click inside the picked slides keeps the pick.
            if !deck.selectedSlides.contains(index) { _select(index) }
            _paneFocused = true
            _showThumbMenu(at: e.position, context: context)
            return
        }
        _endEditing()
        _paneFocused = true
        _deckFocus.requestFocus()
        if _deckChords.shift { deck.selectSlide(index, extend: true); return }
        if _deckChords.primary { deck.selectSlide(index, toggle: true); return }
        // Pressing on one of several picked slides keeps the pick, so the
        // group can be dragged; a plain click without a drag narrows it.
        if !(deck.selectedSlides.count > 1 && deck.selectedSlides.contains(index)) { deck.selectSlide(index) }
        _thumbDrag = (index, e.position.dy, e.position.dx, index, false)
    }

    /// How far down the rail slide `index` starts: the rows above it, section headers (32 each) included and the slides of a collapsed section left out. `index` = the slide count gives the whole length.
    private func _railOffset(of index: Int, itemHeight: Double) -> Double {
        guard !deck.sections.isEmpty else { return Double(index) * itemHeight }
        var y = 0.0
        for (si, sec) in deck.sections.enumerated() {
            y += 32
            for i in deck.slides(inSection: si) {
                if i == index { return y }
                if !sec.collapsed { y += itemHeight }
            }
        }
        return y
    }

    /// `steps` slides down (or up) from `from` among the slides the rail shows.
    private func _railStep(from: Int, steps: Int) -> Int {
        guard !deck.sections.isEmpty else { return max(0, min(deck.slides.count - 1, from + steps)) }
        let shown = deck.slides.indices.filter { i in deck.sectionIndex(ofSlide: i).map { !deck.sections[$0].collapsed } ?? true }
        guard let at = shown.firstIndex(of: from) else { return from }
        return shown[max(0, min(shown.count - 1, at + steps))]
    }

    private func _thumbMove(_ position: Offset, itemHeight: Double) {
        guard var drag = _thumbDrag else { return }
        let dy = position.dy - drag.startY
        if !drag.moved && abs(dy) < 6 { return }
        drag.moved = true
        drag.to = _railStep(from: drag.from, steps: Int((dy / itemHeight).rounded()))
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
        if drag.moved, drag.to != drag.from {
            let picked = deck.selectedSlides
            if picked.count > 1 { deck.moveSelectedSlides(to: picked[0] + (drag.to - drag.from)) }
            else { deck.moveSlide(drag.from, to: drag.to) }
        } else {
            if !drag.moved, deck.selectedSlides.count > 1 { deck.selectSlide(drag.from) } else { setState {} }
        }
    }

    /// A long press or two-finger tap on a thumbnail: the menu a right click on it opens.
    private func _thumbMenuFromTouch(_ index: Int, at point: Offset) {
        guard let context else { return }
        _thumbDrag = nil
        _sorterDrag = nil
        if !deck.selectedSlides.contains(index) { _select(index) }
        _paneFocused = true
        _showThumbMenu(at: point, context: context)
    }

    /// The thumbnail pane's right-click menu.
    private func _showThumbMenu(at point: Offset, context: any BuildContext) {
        let i = deck.current
        let hidden = deck.currentSlide.hidden
        let m = ContextMenuBuilder()
        m.item("New Slide") { [weak self] in self?.deck.addSlide() }
        m.item("Cut") { [weak self] in self?.deck.cutSlides() }
        m.item("Copy") { [weak self] in self?.deck.copySlides() }
        m.item("Paste") { [weak self] in self?._pasteSlides() }
        m.separator()
        m.item("Duplicate Slide") { [weak self] in self?.deck.duplicateSelectedSlides() }
        m.item("Delete Slide", enabled: deck.slides.count > 1) { [weak self] in self?.deck.deleteSelectedSlides() }
        m.separator()
        m.item(hidden ? "Show Slide" : "Hide Slide") { [weak self] in self?.deck.toggleHiddenSelected() }
        m.separator()
        m.item("Add Section") { [weak self] in self?._nameSection(rename: false) }
        m.separator()
        for kind in SlideLayoutKind.allCases {
            m.item("Layout: \(kind.name)", enabled: kind != deck.currentSlide.layout) { [weak self] in
                self?.deck.applyLayout(kind, to: i)
            }
        }
        m.show(_thumbMenu, in: context, at: point)
    }

    /// The right-click menu on the slide: a shape or picture, the text being
    /// edited (with a table's row and column commands inside a table), or the
    /// empty slide. Every row acts on the selection as it stands.
    private func _showSlideMenu(at point: Offset, on shape: SlideShape?) {
        let m = ContextMenuBuilder()
        let deck = self.deck
        if let shape, _active === shape, !_notesActive {
            let c = session.controller
            let has = c.hasSelection
            m.item("Cut", enabled: has) { if let d = c.cutSelectionData() { Clipboard.setData(d) } }
            m.item("Copy", enabled: has) { if let d = c.copySelectionData() { Clipboard.setData(d) } }
            m.item("Paste") { [weak self] in self?.session.onPaste?(false) }
            m.item("Paste: Keep Text Only") { [weak self] in self?.session.onPaste?(true) }
            m.separator()
            m.miniButton(FluentSystemIcons.textBold, "Bold", on: c.selectionAll { $0.bold }) { c.toggleBold() }
            m.miniButton(FluentSystemIcons.textItalic, "Italic", on: c.selectionAll { $0.italic }) { c.toggleItalic() }
            m.miniButton(FluentSystemIcons.textUnderline, "Underline", on: c.selectionAll { $0.underline }) { c.toggleUnderline() }
            if c.isInCell {
                m.separator()
                m.item("Insert Row Above") { c.insertRow(below: false) }
                m.item("Insert Row Below") { c.insertRow(below: true) }
                m.item("Insert Column Left") { c.insertColumn(after: false) }
                m.item("Insert Column Right") { c.insertColumn(after: true) }
                m.item("Delete Row") { c.deleteRow() }
                m.item("Delete Column") { c.deleteColumn() }
            }
        } else if shape != nil, !deck.selection.isEmpty {
            m.item("Cut") { deck.cutShapes() }
            m.item("Copy") { deck.copyShapes() }
            m.item("Paste") { [weak self] in self?._pasteOnSlide() }
            m.item("Duplicate") { deck.duplicateSelection() }
            m.item("Delete") { deck.deleteSelection() }
            m.separator()
            m.item("Bring to Front") { deck.arrange(.front) }
            m.item("Bring Forward") { deck.arrange(.forward) }
            m.item("Send Backward") { deck.arrange(.backward) }
            m.item("Send to Back") { deck.arrange(.back) }
            m.separator()
            m.item("Group", enabled: deck.canGroup) { deck.groupSelection() }
            m.item("Ungroup", enabled: deck.canUngroup) { deck.ungroupSelection() }
            m.item("Regroup", enabled: deck.canRegroup) { deck.regroupSelection() }
            m.separator()
            m.item("Format Shape…") { [weak self] in self?.setState { self?._formatShape = true } }
            m.separator()
            m.item("Rotate Right 90°") { deck.rotateSelection(by: 90) }
            m.item("Rotate Left 90°") { deck.rotateSelection(by: -90) }
            m.item("Flip Vertical") { deck.flipSelection(horizontal: false) }
            m.item("Flip Horizontal") { deck.flipSelection(horizontal: true) }
            m.separator()
            m.item("Align Left") { deck.align(.left) }
            m.item("Align Center") { deck.align(.center) }
            m.item("Align Right") { deck.align(.right) }
            m.item("Align Top") { deck.align(.top) }
            m.item("Align Middle") { deck.align(.middle) }
            m.item("Align Bottom") { deck.align(.bottom) }
            m.item("Distribute Horizontally", enabled: deck.canDistribute) { deck.distribute(horizontal: true) }
            m.item("Distribute Vertically", enabled: deck.canDistribute) { deck.distribute(horizontal: false) }
            if deck.selection.contains(where: { if case .picture = $0.kind { return true } else { return false } }) {
                m.separator()
                m.item("Reset Picture") { deck.resetPictures() }
            }
        } else {
            m.item("Paste") { [weak self] in self?._pasteOnSlide() }
            m.item("Select All") { deck.selectShapes(deck.currentSlide.shapes) }
            m.separator()
            m.item("New Slide") { deck.addSlide() }
            m.item("Duplicate Slide") { deck.duplicateSlide(deck.current) }
        }
        guard let context else { return }
        m.show(_thumbMenu, in: context, at: point)
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
        let picked = Set(deck.selectedSlides)
        func makeTile(_ i: Int, _ slide: Slide) {
            let current = picked.contains(i)
            let activate: () -> Void = { [weak self] in self?.deck.selectSlide(i); self?._deckFocus.requestFocus() }
            let dropHere = _sorterDrag.map { $0.moved && $0.to == i && $0.to != $0.from } ?? false
            let dropBefore = dropHere && _sorterDrag!.to < _sorterDrag!.from
            let bar = Positioned(left: dropBefore ? 3 : nil, top: 12, right: dropBefore ? nil : 3, width: 5, height: h + 8,
                                 child: ColoredBox(color: dropHere ? accent : Color(0x00000000), child: SizedBox(expand: ())))
            tiles.append(Listener(
              key: ValueKey("slide.sorter.\(i)"),
              onPointerDown: { [weak self] e in
                  guard let self, let context = self.context else { return }
                  self._sorterDown(i, e, context: context)
              },
              onPointerMove: { [weak self] e in
                  self?._thumbTouch.moved(e.pointer, e.position)
                  self?._sorterMove(e.position, tile: (w + 32, h + 52))
              },
              onPointerUp: { [weak self] e in
                  self?._thumbTouch.up(e.pointer)
                  self?._sorterMove(e.position, tile: (w + 32, h + 52))
                  self?._sorterUp()
              },
              behavior: .translucent,
            // A reader hears "Slide 3, hidden, selected", not the bare number under the picture.
            child: KeyboardRow(label: "Slide \(i + 1)", activate: activate, child: Semantics(
                label: "Slide \(i + 1)" + (slide.hidden ? ", hidden" : ""), selected: current, onTap: activate,
                excludeSemantics: true, child: GestureDetector(
                key: ValueKey("slide.tile.\(i)"),
                onTap: { [weak self] in
                    guard let self else { return }
                    let now = Date()
                    if let last = self._lastSorterTap, last.index == i, now.timeIntervalSince(last.at) < 0.4 {
                        self._lastSorterTap = nil
                        self.setState { self._sorter = false }
                        return
                    }
                    self._lastSorterTap = (i, now)
                    self._endEditing()
                    if self._deckChords.shift { self.deck.selectSlide(i, extend: true) }
                    else if self._deckChords.primary { self.deck.selectSlide(i, toggle: true) }
                    else { self.deck.selectSlide(i) }
                    self._deckFocus.requestFocus()
                    self._paneFocused = true
                },
                child: Stack(children: [Padding(padding: EdgeInsets(all: 12), child: Column(crossAxisAlignment: .start, children: [
                    DecoratedBox(
                        decoration: BoxDecoration(border: Border.all(
                            color: current ? accent : fluent.resources.controlStrokeColorDefault,
                            width: current ? 3 : 1)),
                        child: Padding(padding: EdgeInsets(all: current ? 1 : 3), child: SizedBox(
                            width: w, height: h,
                            child: ClipRect(child: _dimmedIfHidden(slide, wash: Color(0xFFE6E6E6), child: CustomPaint(
                                painter: SlidePainter(slide: slide, theme: deck.theme, slideSize: deck.slideSize,
                                                      revision: deck.revision, cache: _cache),
                                child: SizedBox(expand: ()))))))),
                    Chrome.vgap(4),
                    Text("\(i + 1)\(slide.hidden ? "  (hidden)" : "")", style: fluent.typography.caption),
                ])), bar]))))))
        }
        if deck.sections.isEmpty {
            for (i, slide) in deck.slides.enumerated() { makeTile(i, slide) }
        } else {
            for (si, sec) in deck.sections.enumerated() {
                let members = deck.slides(inSection: si)
                // A header takes a whole row of the grid.
                tiles.append(_sectionHeader(fluent, si, count: members.count, width: 1200))
                if !sec.collapsed { for i in members { makeTile(i, deck.slides[i]) } }
            }
        }
        let dark = fluent.brightness == .dark
        // A tile: the thumbnail, its frame (8), the number under it (4 and
        // a caption line) and 12 of padding all round.
        _revealSorterTile(rowHeight: h + 52)
        return ColoredBox(color: dark ? Color(0xFF202020) : Color(0xFFE6E6E6), child: SingleChildScrollView(
            controller: _sorterScroll,
            child: Padding(padding: EdgeInsets(all: 16), child: Wrap(children: tiles))))
    }

    /// The sorter's twin of `_revealThumbnail`: the grid comes up, and
    /// stays, with the current slide's row in view. How many tiles a row
    /// holds is read back from the laid-out height, which the grid's width
    /// decided.
    private func _revealSorterTile(rowHeight: Double) {
        let current = deck.current
        FrameCallbackScheduler.shared.addPostFrameCallback { [weak self] _ in
            guard let self, self._sorterScroll.hasClients else { return }
            let pos = self._sorterScroll.position
            let mounted = ObjectIdentifier(pos)
            let allRows = max(1, Int(((pos.maxScrollExtent + pos.viewportDimension - 32) / rowHeight).rounded()))
            self._sorterPerRow = max(1, Int((Double(self.deck.slides.count) / Double(allRows)).rounded(.up)))
            guard current != self._sorterShown || mounted != self._sorterPosition else { return }
            self._sorterShown = current
            self._sorterPosition = mounted
            let count = self.deck.slides.count
            let rows = max(1, Int(((pos.maxScrollExtent + pos.viewportDimension - 32) / rowHeight).rounded()))
            let perRow = max(1, Int((Double(count) / Double(rows)).rounded(.up)))
            let top = 16 + Double(current / perRow) * rowHeight
            let bottom = top + rowHeight
            var target = pos.pixels
            if top < target { target = top - 16 }
            else if bottom > target + pos.viewportDimension { target = bottom - pos.viewportDimension + 16 }
            target = min(max(0, target), pos.maxScrollExtent)
            if abs(target - pos.pixels) > 0.5 { self._sorterScroll.jumpTo(target) }
        }
    }

    // MARK: Notes

    /// The Notes Page view: a portrait page (7.5 x 10 in, as the file's
    /// notesSz), the slide's picture in the upper part, the notes editable below.
    private func _notesPageView(_ fluent: FluentThemeData) -> Widget {
        let slide = deck.currentSlide
        let dark = fluent.brightness == .dark
        _notesTheme.textColor = Color(0xFF1B1B1B)
        _notesTheme.caretColor = _notesTheme.textColor
        let pageW = 480.0, pageH = 640.0
        let picW = 384.0
        let picH = (picW * deck.slideSize.height / deck.slideSize.width).rounded()
        let picLeft = (pageW - picW) / 2, picTop = 48.0
        let bodyTop = picTop + picH + 36
        let page = SizedBox(width: pageW, height: pageH, child: DecoratedBox(
            decoration: BoxDecoration(color: Color(0xFFFFFFFF),
                                      border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1)),
            child: Stack(children: [
                Positioned(left: picLeft, top: picTop, width: picW, height: picH, child: DecoratedBox(
                    decoration: BoxDecoration(border: Border.all(color: Color(0xFF808080), width: 1)),
                    child: ClipRect(child: CustomPaint(
                        painter: SlidePainter(slide: slide, theme: deck.theme, slideSize: deck.slideSize,
                                              revision: deck.revision, cache: _cache),
                        child: SizedBox(expand: ()))))),
                Positioned(left: picLeft, top: bodyTop, right: picLeft, bottom: 48, child: Listener(
                    onPointerDown: { [weak self] _ in self?._editNotes(focus: false) },
                    behavior: .translucent,
                    child: RichEditable(
                        key: ValueKey("page \(slide.id)"),
                        controller: slide.notes, theme: _notesTheme,
                        padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                        focusNode: _notesFocus, autofocus: false, backgroundColor: nil,
                        onShortcut: { [weak self] key, mods in self?._shortcut(key, mods) ?? false },
                        spellChecker: session.checkSpelling ? _spelling : nil))),
            ])))
        return ColoredBox(color: dark ? Color(0xFF202020) : Color(0xFFE6E6E6), child: SingleChildScrollView(
            child: Padding(padding: EdgeInsets(left: 0, top: 20, right: 0, bottom: 20), child: Row(
                mainAxisAlignment: .center, children: [page]))))
    }

    private func _loadOutline() {
        let entries = deck.outlineEntries
        if Outline.entries(from: _outlineCtl.document) == entries { return }
        _outlineSyncing = true
        _outlineCtl.load(Outline.document(entries))
        _outlineSyncing = false
    }

    /// The list was typed in: the deck follows, and the slide under the caret shows.
    private func _outlineEdited() {
        guard _outline, !_outlineSyncing else { return }
        _outlineSyncing = true
        deck.applyOutline(Outline.entries(from: _outlineCtl.document))
        // New rows (and rows whose tag Enter copied) learn their slide's id, so the next edit finds the right slide.
        if Outline.entries(from: _outlineCtl.document).map(\.slideId) != deck.outlineEntries.map(\.slideId) {
            let sel = _outlineCtl.selection
            _outlineCtl.load(Outline.document(deck.outlineEntries))
            _outlineCtl.selection = sel
        }
        let doc = _outlineCtl.document
        let caret = _outlineCtl.selection.caret.paragraph
        var slide = -1
        for (i, p) in doc.paragraphs.enumerated() where i <= caret {
            if p.style.listLevel <= 0 || slide < 0 { slide += 1 }
        }
        if slide >= 0 { deck.selectSlide(min(slide, deck.slides.count - 1)) }
        _outlineSyncing = false
    }

    /// Tab demotes the line one level, Shift+Tab promotes it; a title is level 0.
    private func _outlineShortcut(_ key: KeyData, _ mods: KeyModifiers) -> Bool {
        guard KeyChordTracker.named(key.logical) == .tab else { return false }
        let back = mods.contains(.shift)
        _outlineCtl.applyParagraphStyle { st in
            st.listLevel = max(0, min(5, st.listLevel + (back ? -1 : 1)))
            st.indentLeft = Double(st.listLevel) * Outline.indentPerLevel
        }
        return true
    }

    private func _outlinePane(_ fluent: FluentThemeData) -> Widget {
        let dark = fluent.brightness == .dark
        _outlineTheme.textColor = dark ? Color(0xFFF0F0F0) : Color(0xFF1B1B1B)
        _outlineTheme.caretColor = _outlineTheme.textColor
        return SizedBox(key: ValueKey("outline.pane"), width: 320, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.solidBackgroundFillColorBase,
                border: Border(right: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: RichEditable(
                key: ValueKey("outline.editor"),
                controller: _outlineCtl, theme: _outlineTheme,
                padding: EdgeInsets(left: 12, top: 10, right: 12, bottom: 10),
                focusNode: _outlineFocus, autofocus: false, backgroundColor: nil,
                onShortcut: { [weak self] key, mods in self?._outlineShortcut(key, mods) ?? false },
                onTouchMenu: { [scene = self.officeScene, c = _outlineCtl] rect in scene.showTouchMenu(rect, controller: c) },
                spellChecker: nil)))
    }

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
            onPointerDown: { [weak self] _ in self?._editNotes(focus: false) },
            behavior: .translucent,
            child: RichEditable(
                key: ValueKey(slide.id),
                controller: slide.notes, theme: _notesTheme,
                padding: EdgeInsets(left: 14, top: 10, right: 14, bottom: 10),
                focusNode: _notesFocus, autofocus: false, backgroundColor: nil,
                onShortcut: { [weak self] key, mods in self?._shortcut(key, mods) ?? false },
                onTouchMenu: { [weak notes = slide.notes, scene = self.officeScene] rect in
                    if let notes { scene.showTouchMenu(rect, controller: notes) }
                },
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
        ]
        // (Not in a narrow window: the room goes to the "Slides" button.)
        if !_narrow { left += [Chrome.gap(20), Text("English (United States)", style: dim)] }
        if let message = _status {
            left.append(Chrome.gap(20))
            left.append(Text(message, style: dim))
        }
        var right: [Widget] = []
        if _narrow {
            right += [Chrome.textToggle("Slides", _narrowRail, fluent, style: caption) { [weak self] in
                self?.setState { self?._narrowRail.toggle() }
            }, Chrome.gap(8)]
        }
        right += [
            Chrome.textToggle("Notes", _showNotes, fluent, style: caption) { [weak self] in
                self?.setState { self?._showNotes.toggle() }
            },
            Chrome.gap(8),
            Chrome.toggle(FluentSystemIcons.onePage, "Normal", !_sorter && !deck.notesPageView, fluent) { [weak self] in
                self?.session.onSlidesView?(false)
            },
            Padding(key: ValueKey("view.notesPage.status"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                    child: Chrome.toggle(FluentSystemIcons.document, "Notes Page", deck.notesPageView && !_sorter, fluent) { [weak self] in
                self?.session.onSlidesNotesPage?()
            }),
            Chrome.toggle(FluentSystemIcons.grid, "Slide Sorter", _sorter, fluent) { [weak self] in
                self?.session.onSlidesView?(true)
            },
            Chrome.gap(8),
            Padding(key: ValueKey("zoom.out"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Chrome.icon(FluentSystemIcons.zoomOut, "Zoom Out", fluent) { [weak self] in
                self?.deck.stepViewZoom(-1)
            }),
            // Clicking the percent opens the Zoom dialog, as in PowerPoint.
            SizedBox(key: ValueKey("zoom.percent"), width: 44, height: nil,
                     child: Semantics(label: "Zoom", value: "\(deck.viewPercent)%", button: true,
                                      onTap: { [weak self] in self?.session.onZoomDialog?() }, excludeSemantics: true,
                                      child: GestureDetector(onTap: { [weak self] in self?.session.onZoomDialog?() },
                                                             child: Text("\(deck.viewPercent)%", style: caption)))),
            Padding(key: ValueKey("zoom.in"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Chrome.icon(FluentSystemIcons.zoomIn, "Zoom In", fluent) { [weak self] in
                self?.deck.stepViewZoom(1)
            }),
            Padding(key: ValueKey("zoom.fit"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Chrome.icon(FluentSystemIcons.pageFit, "Fit slide to window", fluent) { [weak self] in
                self?.deck.fitView()
            }),
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
