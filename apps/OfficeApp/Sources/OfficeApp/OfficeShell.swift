// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The window: title row, ribbon, find bar, ruler, the page area, status
// bar — and Backstage over all of it for File. The shell owns the session
// and rebuilds chrome only when the toolbar summary changes, so typing
// never rebuilds anything but the editor's own painter.

import Flutter
import FluentSystemIcons
import OfficeText
import FlutterSwiftBridge
import Foundation
#if os(WASI)
import FlutterWeb
#endif

final class OfficeShell: StatefulWidget {
    let initialPath: String?
    /// Hand the window to the other kind: a new or opened deck.
    let onSwitch: ((DocumentKind, String?) -> Void)?
    /// Start on a blank document, not on the welcome page or a recovery
    /// copy: the window came here from Slides' "Blank document".
    let startBlank: Bool
    let startHome: Bool
    /// A document owned by something other than a file (a wiki page):
    /// opened as given, saved back to its owner, closed to its owner.
    let hosted: HostedDocument?
    /// Backstage's "Open site…" picked a site folder: the window becomes
    /// its reader (OfficeRoot).
    let onOpenSite: ((String, Bool) -> Void)?

    init(initialPath: String?, startBlank: Bool = false, startHome: Bool = false, hosted: HostedDocument? = nil,
         onSwitch: ((DocumentKind, String?) -> Void)? = nil, onOpenSite: ((String, Bool) -> Void)? = nil) {
        self.initialPath = initialPath
        self.startBlank = startBlank
        self.startHome = startHome
        self.hosted = hosted
        self.onSwitch = onSwitch
        self.onOpenSite = onOpenSite
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        return OfficeShellState()
    }
}

final class OfficeShellState: State<StatefulWidget> {
    private let _leakProbe = LeakProbe("OfficeShellState")
    let session = OfficeSession()
    private var _tab = RibbonTab.home
    private var _ribbonCollapsed = false
    private var _backstage: BackstagePage? = nil
    private var _findOpen = false
    private var _findReplace = false
    private var _findStatus = ""
    private(set) var _status: String? = nil
    private var _statusGeneration = 0
    private var _savedRevision = 0
    /// The revision the page's recovery copy holds (a browser tab): a flush
    /// when the tab is hidden writes only a copy that is behind.
    private var _keptRevision: Int?
    private var _recent: [String] = []
    private let _search = TextEditingController()
    private var _ribbonBeforeReading = false
    private let _findQuery = TextEditingController()
    /// The document's own focus, so closing a bar can hand the keyboard back.
    private let _editorFocus = FocusNode(debugLabel: "Writer document")
    private let _findReplacement = TextEditingController()
    private var _headerFooterStripOpen = false
    /// The header and footer strip, with Word's Header & Footer tab beside it while it is open.
    private var _headerFooterOpen: Bool {
        get { _headerFooterStripOpen }
        set {
            _headerFooterStripOpen = newValue
            session.headerFooterOpen = newValue
            if newValue { _tab = .headerFooter } else if _tab == .headerFooter { _tab = .home }
        }
    }
    /// The strip's text and look into the document, and the strip closed (its tick, and the tab's Close button).
    private func _applyHeaderFooterStrip() {
        controller.applyHeaderFooterStrip(
            header: _headerText.text, footer: _footerText.text,
            headerLook: _headerLook, footerLook: _footerLook,
            headerLocked: controller.document.hasRichHeaderFooter(.header),
            footerLocked: controller.document.hasRichHeaderFooter(.footer))
        setState { _headerFooterOpen = false }
    }
    private var _shortcutsOpen = false
    private var _cardLink: String? = nil      // the link under the caret, shown on the link card
    private var _cardDismissed = false
    private var _hoverCard: String? = nil     // a link the pointer rested on; stays until the caret or another link replaces it
    private var _linkDialogOpen = false
    private var _colorOpen = false
    private var _paragraphOpen = false
    private var _tablePropsOpen = false
    private var _findDialogOpen = false
    private var _symbolOpen = false
    private var _fontOpen = false
    private var _pageSetupOpen = false
    private var _columnsOpen = false
    private var _insertTableOpen = false
    private var _splitCellOpen = false
    /// The clipboard while Paste Special is open.
    private var _pasteSpecialData: ClipboardData?
    private var _formulaOpen = false
    private var _contentsOpen = false
    /// Table of Figures: the contents dialog opens for these caption labels.
    private var _figureLabels: [String]?
    private var _noteOptionsOpen = false
    private var _tableTool: String? = nil
    private var _sortTable: SortTableValues? = nil   // the open Sort dialog
    private var _convertTextTable: Bool? = nil   // the open Convert dialog: true to a table, false to text
    private var _bordersOpen = false
    private var _printOpen = false
    private var _pictureDialog: PictureDialogKind?
    /// A text box being typed into in place: the box, where it is drawn (in the page area), and the document's own controller
    /// while `session.controller` is the box's.
    var _boxEdit: (index: Int, inline: String?, rect: Rect, main: RichDocumentController, autoFit: Bool, child: Int?)?
    var _boxContentHeight: Double?
    /// W-TB-5: where in the box editor the click that opened it landed (a table nested in a cell), for the caret.
    var _boxCaretAt: Offset?
    /// The page's layout of the nested table being edited (`RichLayout.boxFrame`): the editor sets it the same way.
    var _boxRules: RichLayout?
    private let _boxFocus = FocusNode(debugLabel: "Text box")
    /// Set while the picker is open for Change Picture: the picture (paragraph, inline id) the chosen file replaces.
    private var _replaceTarget: (index: Int, inline: String?)?
    private var _numberingValueOpen = false
    private var _multilevelOpen = false
    private var _commentOpen = false
    private var _dateTimeOpen = false
    private var _fieldOpen = false
    private var _bookmarkOpen = false, _crossReferenceOpen = false, _captionOpen = false
    /// W-PG-3: which of Design's Watermark and Page Borders dialogs, or Layout's Line Numbers, is open.
    enum PageDesignDialog { case watermark, pageBorders, lineNumbers }
    private(set) var _pageDesign: PageDesignDialog?
    private var _propertiesOpen = false
    private var _listSymbolPick: ((String, String?) -> Void)? = nil   // the Symbol picker is open for the Define Bullet dialog
    private var _listFormatOpen: Bool? = nil   // the dialog is open: true for a bullet
    var _noteOpen: NoteReference? = nil
    private var _noteBox = Rect.zero
    private var _noteKeys: Int?
    /// The comment card open over a balloon: the thread's top comment, where its balloon is, its text and a reply.
    var _cardOpen: String? = nil
    private var _cardBox = Rect.zero
    private var _cardKeys: Int?
    private let _cardText = TextEditingController()
    private let _replyText = TextEditingController()
    private let _noteText = TextEditingController()
    private var _newStyleOpen = false
    private let _colorText = TextEditingController()
    private var _styleOpen: String? = nil
    private var _linkHover: String? = nil
    /// The window is narrower than a side pane and a page fit side by side (a Split View pane on an iPad): panes become a
    /// bottom sheet.
    private var _narrow = false
    /// The selected chart's data pane (Chart Design > Edit Data) is open.
    private var _chartData = false
    private static let narrowBelow = 600.0
    private var _autosaveGeneration = 0
    private let _contextMenu = FlyoutController()
    /// While the Paste Options menu is open: its K, M, U, T keys.
    private var _pasteKeys: Int?
    private let _spelling: RichSpellChecker? = makeSpellChecker()
    /// Set when the open document came from a recovery copy: AutoSave then
    /// refreshes only the copy until the user saves for real.
    private var _recovered = false
    /// In a browser tab: the page's number for the file this document was
    /// opened from or saved to through the browser's file pickers. Save
    /// writes back to it; nil means Save asks for a place (or downloads).
    private var _browserHandle: Int?
    private let _headerText = TextEditingController()
    private let _footerText = TextEditingController()
    private var _headerLook = RichDocumentController.HeaderFooterLook()
    private var _footerLook = RichDocumentController.HeaderFooterLook()

    private var controller: RichDocumentController { session.controller }

    // MARK: Lifecycle

    override func initState() {
        super.initState()
        OfficeFonts.register()
        bind(_editorFocus)
        trackDocumentPath(session)
        _recent = _loadRecent()
        _wireSession()
        officeScene.registerFlush(owner: self) { [weak self] in self?._autosaveNow() }
        officeScene.setPictureDrop({ [weak self] path in self?._insertPicture(path) }, owner: self)
        controller.addListener({ [weak self] in self?._publishToolbar() }, owner: self)
        _publishToolbar()
        // `starling.debug('layout')` from the browser's console or a script:
        // the open document's lines and pages, to diff against
        // `OfficeApp --layout` natively.
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
            guard let self, kind == "layout" else { return nil }
            return OfficeLayoutDump.text(self.controller.document, pageSetup: self.session.pageSetup)
        }
        let env = ProcessInfo.processInfo.environment
        if let hosted = (widget as! OfficeShell).hosted {
            controller.load(hosted.document)
            if let selection = hosted.initialSelection {
                controller.selection = selection
                let expectedSelection = controller.selection
                let revision = controller.revision
                // Reveal after the editor has a viewport. A newer edit or
                // caret move takes precedence over this initial placement.
                FrameCallbackScheduler.shared.addPostFrameCallback { [weak self] _ in
                    guard let self, self.mounted, self.controller.revision == revision,
                          self.controller.selection == expectedSelection else { return }
                    self.controller.pendingReveal = .top
                    self.controller.notifyListeners()
                }
                PlatformDispatcher.instance.scheduleFrame()
            }
            if let setup = hosted.pageSetup { session.pageSetup = setup }
            session.titleOverride = hosted.title
            session.hostName = hosted.ownerName
            session.hostReturnLabel = hosted.returnLabel
            session.onSaveBeforeLeaving = { [weak self] next in self?._save(afterSaving: next) }
            // The way back asks about unsaved changes first, as Close does.
            session.onClose = { [weak self] in self?.session.replacing { hosted.close() } }
        } else if let pages = env["OFFICE_DEMO_PAGES"].flatMap(Int.init), pages > 0 {
            controller.load(DemoDocument.make(pages: pages))
        } else if let path = (widget as! OfficeShell).initialPath {
            // Bytes from the browser's picker that crossed a kind switch
            // (a .docx picked in Slides) arrive by name, not on disk.
            if let data = PickedFile.take(path) { _open(path, data: data, handle: PickedFile.takenHandle) } else { _open(path) }
        } else if (widget as! OfficeShell).startBlank {
            var blank = RichDocument()
            blank.styles = OfficeStyles.sheet
            controller.load(blank)
        } else if let row = OfficeHost.browserRecovery?.take("docx"),
                  let opened = try? OfficeFormats.read(row.data, named: row.name) {
            // A tab closed with unsaved changes: its copy, under the name it would have saved as.
            controller.load(opened.document)
            if let setup = opened.pageSetup { session.pageSetup = setup }
            session.path = row.name
            _recovered = true
            session.dirty = true
            _flash("Restored an unsaved document — Save to keep it")
        } else if let onSwitch = (widget as! OfficeShell).onSwitch,
                  let (kind, row) = OfficeHost.browserRecovery.flatMap({ browser in
                      browser.take("pptx").map { (DocumentKind.presentation, $0) }
                          ?? browser.take("xlsx").map { (DocumentKind.workbook, $0) } }) {
            // A tab always starts in Writer: a deck or workbook left unsaved by a closed tab goes on to Slides or
            // Sheets, which opens it unsaved. (Switched after this frame: the window is mid-build now.)
            controller.load(WelcomeDocument.make())
            PickedFile.hand(row.name, row.data, recovered: true)
            FrameCallbackScheduler.shared.addPostFrameCallback { _ in onSwitch(kind, row.name) }
            PlatformDispatcher.instance.scheduleFrame()
        } else if FileManager.default.fileExists(atPath: _recoveryPath(for: nil)),
                  let opened = try? OfficeFormats.read(_recoveryPath(for: nil)) {
            // Last time ended with an unsaved untitled document.
            controller.load(opened.document)
            _recovered = true
            _savedRevision = controller.revision - 1
            session.dirty = true
            _flash("Restored an unsaved document — Save to keep it")
        } else {
            controller.load(WelcomeDocument.make())
        }
        if ProcessInfo.processInfo.environment["OFFICE_PROBE_PLATFORM"] != nil {
            _probePlatformMessages()
        }
        // A restored document is unsaved until the user saves it.
        _savedRevision = _recovered ? controller.revision - 1 : controller.revision
        if (widget as! OfficeShell).startHome { _backstage = .home }
        session.summary = session.summarize()
        controller.addListener { [weak self] in
            guard let self else { return }
            if let last = self.controller.document.lastSectionPage, last != self.session.pageSetup {
                self.setState { self.session.pageSetup = last }
            }
            let under = self.controller.currentLink
            if under != self._cardLink { self.setState { self._cardLink = under; self._hoverCard = nil; self._cardDismissed = false } }
            let s = self.session.summarize()
            let dirty = self.controller.revision != self._savedRevision
            if dirty { self._scheduleAutosave() }
            if s != self.session.summary || dirty != self.session.dirty {
                self.setState {
                    // Selecting a picture opens its tab; leaving it returns Home.
                    if s.imageIndex != nil, self.session.summary.imageIndex == nil { self._tab = self.session.imageTab(at: s.imageIndex, inline: s.inlineImageID) }
                    if s.imageIndex == nil, self._tab == .pictureFormat || self._tab == .shapeFormat { self._tab = .home }
                    if !s.inCell, self._tab == .tableLayout { self._tab = .home }
                    self.session.summary = s
                    self.session.dirty = dirty
                }
            }
        }
    }

    /// The buttons a native toolbar over the keyboard shows, with the caret's
    /// state: the same questions the ribbon asks. Nothing happens on a platform
    /// with no such toolbar.
    private func _publishToolbar() {
        guard officeScene.toolbarChanged != nil else { return }
        let c = controller
        let style = c.currentCharStyle
        let list = c.document.paragraphs[min(c.selection.focus.paragraph, c.document.paragraphs.count - 1)].style.list
        // What the selection is in: a table cell gets row and column commands, a picture its size and removal.
        var context: [OfficeScene.ToolbarButton] = []
        if c.isInCell {
            context += [
                .init(id: "ctx-row-add", title: "Insert Row Below", symbol: "plus.rectangle") { [weak c] in c?.insertRow(below: true) },
                .init(id: "ctx-row-del", title: "Delete Row", symbol: "minus.rectangle") { [weak c] in c?.deleteRow() },
                .init(id: "ctx-col-add", title: "Insert Column Right", symbol: "plus.rectangle.portrait") { [weak c] in c?.insertColumn(after: true) },
                .init(id: "ctx-col-del", title: "Delete Column", symbol: "minus.rectangle.portrait") { [weak c] in c?.deleteColumn() },
                .init(id: "ctx-cell-merge", title: "Merge Cells", symbol: "rectangle.split.2x1") { [weak c] in c?.mergeCells() },
                .init(id: "ctx-table-del", title: "Delete Table", symbol: "trash.slash") { [weak c] in c?.deleteTable() },
            ]
        }
        // A picture or shape, whole-paragraph or inline in a line of text: its size, wrap, crop and aspect, and for a shape its colours.
        let hit = c.selectedInlineImage
        let pic: (index: Int, inline: String?)? = c.selectedImageIndex.map { ($0, nil) } ?? hit.map { ($0.paragraph, $0.id) }
        if let (i, inline) = pic, i < c.document.paragraphs.count, inline != nil || !session.isNestedTableBlock(i),
           let image = inline.map({ c.document.paragraphs[i].inlineImages[$0] }) ?? c.document.paragraphs[i].image {
            let isShape = session.imageTab(at: i, inline: inline) == .shapeFormat
            let wrap = c.pictureWrap(at: i, inline: inline)
            var wraps: [OfficeScene.ToolbarButton] = [
                .init(id: "ctx-wrap-inline", title: "In Line with Text", symbol: "", isOn: wrap == nil, isEnabled: wrap != nil) { [weak c] in _ = c?.setInLine(at: i, inline: inline) },
            ]
            wraps += PictureWrap.allCases.map { w in
                .init(id: "ctx-wrap-\(w.rawValue)", title: w.title, symbol: "", isOn: wrap == w, isEnabled: wrap != w) { [weak c] in _ = c?.setPictureWrap(at: i, inline: inline, w) }
            }
            // As the ribbon: only a picture in a line of text, or one that already floats, has a wrap to choose.
            if c.isInLine(at: i, inline: inline) || wrap != nil {
                context.append(.init(id: "ctx-pic-wrap", title: "Wrap Text", symbol: "text.below.photo", children: wraps) {})
            }
            if isShape {
                context.append(OfficeHost.colorButton(id: "ctx-shape-fill", title: "Shape Fill", symbol: "paintpalette", none: "No Fill") { [weak c] color in _ = c?.setShapeFill(at: i, inline: inline, color) })
                context.append(OfficeHost.colorButton(id: "ctx-shape-outline", title: "Shape Outline", symbol: "square.dashed", none: "No Outline") { [weak c] color in _ = c?.setShapeOutline(at: i, inline: inline, color) })
            } else {
                context.append(.init(id: "ctx-pic-crop", title: "Crop", symbol: "crop") { [weak session] in session?.onPictureDialog?(.crop) })
            }
            context += [
                .init(id: "ctx-pic-fit", title: "Fit Picture to Width", symbol: "arrow.left.and.right") { [weak c, weak session] in
                    guard let c, let session else { return }
                    let w = session.pageSetup.columnWidth
                    if let inline { c.setInlineImageSize(in: i, id: inline, width: w, height: w * image.height / max(1, image.width)) }
                    else { c.setImageSize(at: i, width: w, height: w * image.height / max(1, image.width)) }
                },
                .init(id: "ctx-pic-lock", title: c.pictureAspectLock ? "Unlock Aspect Ratio" : "Lock Aspect Ratio",
                      symbol: c.pictureAspectLock ? "lock" : "lock.open") { [weak session] in session?.onToggleAspectLock?() },
                .init(id: "ctx-pic-del", title: isShape ? "Delete Shape" : "Delete Picture", symbol: "trash") { [weak c] in c?.deleteForward() },
            ]
        }
        officeScene.publishToolbar(.init(
            canUndo: c.canUndo, canRedo: c.canRedo,
            bold: style.bold, italic: style.italic, underline: style.underline,
            hasLists: true, list: list,
            // (Weak: the buttons live in UIKit's menu objects, which can outlast the window; a strong controller kept a
            // closed window's whole document in memory.)
            undo: { [weak c] in c?.undo() }, redo: { [weak c] in c?.redo() },
            toggleBold: { [weak c] in c?.toggleBold() }, toggleItalic: { [weak c] in c?.toggleItalic() },
            toggleUnderline: { [weak c] in c?.toggleUnderline() }, toggleList: { [weak c] in c?.toggleList($0) },
            context: context), owner: self)
    }

    override func dispose() {
        _endPasteKeys()
        officeScene.publishToolbar(nil, owner: self)
        officeScene.unregisterFlush(owner: self)
        officeScene.setPictureDrop(nil, owner: self)
        officeScene.setDocumentPath(nil, owner: self)
        _search.dispose()
        _findQuery.dispose()
        _findReplacement.dispose()
        _editorFocus.dispose()
        _headerText.dispose()
        _noteText.dispose()
        _cardText.dispose()
        _replyText.dispose()
        _colorText.dispose()
        _footerText.dispose()
        super.dispose()
    }

    private func _wireSession() {
        // W-PG-3: the window shows the page colour and page borders, as Word's does.
        session.theme.drawsPageDesign = true
        if session.kind == .document {
            // Chart Design > Edit Data opens the chart's data beside the page; a chart part set by an edit, an undo or a
            // redo is read again, so the chart draws what its part now says.
            session.onChartData = { [weak self] show in self?.setState { self?._chartData = show } }
            session.controller.onKeptPartChange = { [weak self] path, data in
                guard let self else { return }
                WordChartEdit.partChanged(path, data, in: self.session.controller.document)
            }
        }
        session.onZoom = { [weak self] z in
            guard let self else { return }
            self.setState { self.session.zoom = max(0.5, min(3.0, (z * 10).rounded() / 10)) }
        }
        session.onViewMode = { [weak self] m in
            guard let self else { return }
            self.setState {
                // Read Mode folds the ribbon away; leaving it puts the
                // ribbon back as it was, not folded for good.
                let was = self.session.viewMode
                if m == .readMode, was != .readMode {
                    self._ribbonBeforeReading = self._ribbonCollapsed
                    self._ribbonCollapsed = true
                } else if was == .readMode, m != .readMode {
                    self._ribbonCollapsed = self._ribbonBeforeReading
                }
                self.session.viewMode = m
                self.controller.readOnly = m == .readMode
            }
        }
        session.onToggleRuler = { [weak self] in
            guard let self else { return }
            self.setState { self.session.showRuler.toggle() }
        }
        session.onToggleAspectLock = { [weak self] in
            guard let self else { return }
            self.session.controller.pictureAspectLock.toggle()
            self.setState { self.session.summary = self.session.summarize() }
        }
        session.onToggleNavigation = { [weak self] in
            guard let self else { return }
            self.setState { self.session.showNavigation.toggle() }
        }
        session.onToggleStyles = { [weak self] in
            guard let self else { return }
            self.setState { self.session.showStyles.toggle() }
        }
        session.onToggleSpelling = { [weak self] in
            guard let self else { return }
            self.setState { self.session.checkSpelling.toggle() }
        }
        session.onToggleMarks = { [weak self] in
            guard let self else { return }
            self.setState {
                self.session.showMarks.toggle()
                self.session.theme.showMarks = self.session.showMarks
            }
            self.controller.invalidateLayout()
        }
        session.onToggleTrackChanges = { [weak self] in
            guard let self else { return }
            let on = !self.controller.document.trackRevisions
            self.setState { self.controller.setTrackRevisions(on) }
            self.session.onStatus?(on ? "Track Changes on" : "Track Changes off")
        }
        session.onNewComment = { [weak self] in
            guard let self, !self.controller.readOnly else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._commentOpen = true }
        }
        session.onShowComments = { [weak self] in
            guard let self else { return }
            self.setState { self.session.theme.showComments.toggle() }
            self.controller.invalidateLayout()
            self.session.onStatus?(self.session.theme.showComments ? "Comments shown" : "Comments hidden")
        }
        session.onMarkup = { [weak self] mode in
            guard let self else { return }
            self.setState { self.session.theme.markup = mode }
            self.controller.invalidateLayout()
        }
        session.onFormatPainter = { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let double = now - self.session.lastPainterPress < 0.45
            self.session.lastPainterPress = now
            if self.session.paintedStyle != nil && double {
                self.session.paintSticky = true   // second press: keep painting
                self._flash("Format Painter on: Esc to stop")
            } else if self.session.paintedStyle != nil {
                self._cancelPainter()
            } else {
                self.session.paintedStyle = self.controller.copyFormat()
                self.session.paintSticky = false
                self._flash("Format Painter: select the text to paint")
            }
            self.setState { self.session.summary = self.session.summarize() }
        }
        session.onPageSetup = { [weak self] p in
            guard let self else { return }
            self.setState { self.session.applyPageSetup(p) }
        }
        session.onBackstage = { [weak self] open in
            guard let self else { return }
            self.setState { self._backstage = open ? .home : nil }
        }
        session.onNew = { [weak self] in self?._new() }
        session.guardWindowClose()
        session.routeFieldChords()
        session.homeForKeys { [weak self] in
            guard let self, self.mounted, self._backstage == nil else { return nil }
            return self._editorFocus
        }
        session.onNewKind = { [weak self] kind in
            guard let self else { return }
            if kind == .document { self._new() } else { (self.widget as! OfficeShell).onSwitch?(kind, nil) }
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
            // elsewhere our name-and-format box, and a download.
            if let files = OfficeHost.browserFiles {
                if files.canPickPlace { self._saveAsInBrowser(files) } else { self.setState { self._backstage = .saveAs } }
                return
            }
            #if !os(WASI)
            // A host with its own picker (the iPad's) names and places the
            // copy, and the editor carries on in it.
            if let ask = officeScene.exportRequested {
                let name = self.session.path.map { $0.lastPathComponent }
                    ?? self.session.title.deletingPathExtension + ".docx"
                ask(name, { [weak self] path, finished in
                    guard let self else { finished(false); return }
                    finished((try? OfficeFormats.write(self.controller.document, to: path,
                                                       pageSetup: self.session.pageSetup)) != nil)
                }, true) { _ in }
                return
            }
            self.setState { self._backstage = .saveAs }
            #endif
        }
        session.onExport = { [weak self] ext in self?._export(ext) }
        session.onShare = { [weak self] ext in self?._export(ext, share: true) }
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
        session.onShortcuts = { [weak self] in self?.setState { self?._backstage = nil; self?._shortcutsOpen = true } }
        session.onFind = { [weak self] replace in self?._openFind(replace: replace) }
        session.onHeaderFooter = { [weak self] in
            guard let self else { return }
            self._headerText.text = self.controller.document.header
            self._footerText.text = self.controller.document.footer
            self._headerLook = self.controller.headerFooterLook(.header)
            self._footerLook = self.controller.headerFooterLook(.footer)
            self.setState { self._headerFooterOpen = true }
        }
        session.onCloseHeaderFooter = { [weak self] in self?._applyHeaderFooterStrip() }
        session.onLink = { [weak self] in self?._openLink() }
        session.onInsertNote = { [weak self] kind in
            guard let self else { return }
            self.controller.insertNote(kind)
            if let n = self.controller.noteAtCaret() { self._openNote(n) }
        }
        session.onEditNote = { [weak self] in
            guard let self else { return }
            if let n = self.controller.noteAtCaret() { self._openNote(n) } else { self._flash("Put the caret next to a footnote or endnote mark") }
        }
        session.onBookmarkDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._bookmarkOpen = true }
        }
        session.onCrossReferenceDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._crossReferenceOpen = true }
        }
        session.onCaptionDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._captionOpen = true }
        }
        session.onWatermark = { [weak self] choice in self?._applyWatermark(choice) }
        for (hook, kind) in [(\OfficeSession.onWatermarkDialog, PageDesignDialog.watermark), (\.onPageBordersDialog, .pageBorders), (\.onLineNumbersDialog, .lineNumbers)] {
            session[keyPath: hook] = { [weak self] in
                guard let self else { return }
                self.controller.breakUndoCoalescing()
                self.setState { self._pageDesign = kind }
            }
        }
        session.onFieldDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._fieldOpen = true }
        }
        session.onDateTimeDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._dateTimeOpen = true }
        }
        session.onPropertiesDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._propertiesOpen = true }
        }
        session.onUpdateFields = { [weak self] in self?._updateFields(everywhere: true) }
        session.onSymbolDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._symbolOpen = true }
        }
        session.onParagraphDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._paragraphOpen = true }
        }
        session.onFontDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._fontOpen = true }
        }
        session.onPageSetupDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._pageSetupOpen = true }
        }
        session.onColumnsDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._columnsOpen = true }
        }
        session.onInsertTableDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._insertTableOpen = true }
        }
        session.onFormulaDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._formulaOpen = true }
        }
        session.onSortTableDialog = { [weak self] in
            guard let self, self.controller.canSortTable else { return }
            var v = SortTableValues()
            v.columnCount = max(1, self.controller.currentTableRange.flatMap { r in self.controller.document.paragraphs[r.lowerBound].cell.map { self.controller.document.columnCount(of: $0.table) } } ?? 1)
            v.keys[0].column = min(v.columnCount, (self.controller.currentCell?.column ?? 0) + 1)
            self.setState { self._sortTable = v }
        }
        session.onConvertTextTableDialog = { [weak self] toTable in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._convertTextTable = toTable }
        }
        session.onInsertContents = { [weak self] options in self?._insertContents(options) }
        session.onNoteOptions = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._noteOptionsOpen = true }
        }
        session.onNextNote = { [weak self] kind in
            self?.controller.goToNextNote(kind)
            self?._editorFocus.requestFocus()
        }
        session.onContentsDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._contentsOpen = true; self._figureLabels = nil }
        }
        session.onFiguresDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            let labels = self.controller.crossReferenceTypes().compactMap { t -> String? in if case .caption(let l) = t { return l }; return nil }
            self.setState { self._contentsOpen = true; self._figureLabels = labels }
        }
        session.onUpdateContents = { [weak self] pagesOnly in
            guard let self else { return }
            let labels = PdfExport.pageLabels(self.controller.document, pageSetup: self.session.pageSetup, theme: self.session.theme)
            if !self.controller.updateTableOfContents(pagesOnly: pagesOnly, width: self.session.pageSetup.columnWidth, pageOf: labels, layout: { PdfExport.pageLabels($0, pageSetup: self.session.pageSetup, theme: self.session.theme) }) {
                self._flash("There is no table of contents in this document")
            }
        }
        session.onSplitCellDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._splitCellOpen = true }
        }
        session.onTableTool = { [weak self] tool in
            guard let self else { return }
            self.setState { self._tableTool = self._tableTool == tool ? nil : tool; self.session.tableTool = self._tableTool }
        }
        session.onTablePropertiesDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._tablePropsOpen = true }
        }
        session.onBordersShadingDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._bordersOpen = true }
        }
        session.onPictureDialog = { [weak self] kind in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._pictureDialog = kind }
        }
        session.onListFormatDialog = { [weak self] bullet in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._listFormatOpen = bullet }
        }
        session.onMultilevelDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._multilevelOpen = true }
        }
        session.onNumberingValueDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._numberingValueOpen = true }
        }
        session.onNewStyleDialog = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._newStyleOpen = true }
        }
        session.onMoreColors = { [weak self] in
            guard let self else { return }
            self._colorText.text = self.controller.currentCharStyle.color.map(ColorBar.hex) ?? ""
            self.setState { self._colorOpen = true }
        }
        session.onModifyStyle = { [weak self] id in
            guard let self else { return }
            self.controller.breakUndoCoalescing()   // a new strip is a new undo step
            self.setState { self._styleOpen = id }
        }
        session.onPaste = { [weak self] plain in self?._paste(plain: plain) }
        session.onPasteMode = { [weak self] mode in self?._paste(mode: mode) }
        session.onPasteSpecial = { [weak self] in self?._openPasteSpecial() }
        session.onInsertPicture = { [weak self] in
            guard let self else { return }
            if let ask = self.officeScene.pictureRequested {
                ask { [weak self] path in if let path { self?._insertPicture(path) } }
                return
            }
            self.setState { self._backstage = .insertPicture }
        }
        session.onChangePicture = { [weak self] in
            guard let self, let i = self.session.summary.imageIndex else { return }
            self._replaceTarget = (i, self.session.summary.inlineImageID)
            if let ask = self.officeScene.pictureRequested {
                ask { [weak self] path in if let path { self?._insertPicture(path) } else { self?._replaceTarget = nil } }
                return
            }
            self.setState { self._backstage = .insertPicture }
        }
        session.onStatus = { [weak self] msg in self?._flash(msg) }
        session.onToggleAutoSave = { [weak self] in
            guard let self else { return }
            self.setState { self.session.autoSave.toggle() }
            self._flash(self.session.autoSave ? "AutoSave on" : "AutoSave off — a recovery copy is still kept")
            self._scheduleAutosave()
        }
        session.onPrint = { [weak self] in
            guard let self else { return }
            self.controller.breakUndoCoalescing()
            self.setState { self._backstage = nil; self._printOpen = true }
        }
    }

    // MARK: Diagnostics

    /// OFFICE_PROBE_PLATFORM=1: ask the platform for the clipboard text over
    /// the `flutter/platform` channel (JSON method codec) and print what
    /// comes back, then quit — proof that platform messages travel both
    /// ways without a screen.
    private func _probePlatformMessages() {
        let request = Data("{\"method\":\"Clipboard.getData\",\"args\":\"text/plain\"}".utf8)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            PlatformDispatcher.instance.sendPlatformMessage("flutter/platform", request) { reply in
                let text = reply.map { String(decoding: $0, as: UTF8.self) } ?? "<no reply>"
                fputs("[probe] flutter/platform Clipboard.getData -> \(text)\n", stderr)
                exit(0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5)) {
                fputs("[probe] timed out waiting for a reply\n", stderr)
                exit(1)
            }
        }
    }

    // MARK: Print

    /// Render to a PDF in the temporary directory and hand it to the host's
    /// print dialog.
    /// Runs `work` from the run loop, not from the block it was asked in. A PDF still waits for the pictures a
    /// header's metafile or a drawing group decodes on the main queue (the body's, headers' and text boxes' reach
    /// it through the layout's mailbox), by spinning the run loop, which cannot drain a serial queue it is itself
    /// running a block of; asked from one (the driven tap of the simulator tests is one) that wait runs out its
    /// eight seconds and the picture prints as a grey box. A plain call outside iOS, where nothing is known to.
    private func _outOfThisBlock(_ work: @escaping () -> Void) {
        #if os(iOS)
        RunLoop.main.perform(work)
        #else
        work()
        #endif
    }

    private func _print(pages: [Int]) -> String {
        // A host that prints bytes (the browser): the same PDF as Export,
        // waiting for pictures and fonts, handed over instead of downloaded.
        if let printBytes = hostPrintPDFBytes {
            #if os(WASI)
            let path = "/print/" + session.title + ".pdf"
            #else
            let path = NSTemporaryDirectory() + "office-print-\(ProcessInfo.processInfo.processIdentifier).pdf"
            #endif
            let name = session.title + ".pdf"
            PdfExport.writeWhenDecoded(controller.document, pageSetup: session.pageSetup, theme: session.theme,
                                       to: path, title: session.title, printPages: pages,
                                       deliver: { data in printBytes(data, name) }) { [weak self] ok in
                if !ok { self?._flash("Could not render the document for printing") }
            }
            return ""
        }
        #if os(WASI)
        return "No print dialog on this host"
        #else
        let path = NSTemporaryDirectory() + "office-print-\(ProcessInfo.processInfo.processIdentifier).pdf"
        guard PdfExport.write(controller.document, pageSetup: session.pageSetup, theme: session.theme,
                              to: path, title: session.title, printPages: pages) else {
            return "Could not render the document for printing"
        }
        if let print = hostPrintPDF { print(path); return "" }
        return "No print dialog on this host"
        #endif
    }

    private var _printHooks: PrintHooks {
        PrintHooks(unit: "Pages", total: max(1, session.pageInfo.count), current: session.pageInfo.page,
                   hostCanPrint: hostCanPrintPDF, print: { [weak self] pages, _ in
                       // Off iOS the work runs at once and its message comes back to the dialog.
                       var result = ""
                       self?._outOfThisBlock { result = self?._print(pages: pages) ?? "" }
                       return result
                   })
    }

    // MARK: AutoSave and recovery

    /// Where a document's recovery copy lives: beside a titled document as
    /// `name.docx~`, or under ~/.config/starling/office-recovery for one
    /// that has no file yet.
    private func _recoveryPath(for path: String?) -> String {
        if let path { return path + "~" }
        #if os(WASI)
        return "/office-recovery/untitled.docx~"  // never written: see _scheduleAutosave
        #else
        return OfficeRecovery.untitled("docx")
        #endif
    }

    /// Two seconds after the last edit: AutoSave writes the file itself
    /// when it is on and the document has one; either way the recovery
    /// copy is refreshed.
    private func _scheduleAutosave() {
        // A hosted document has no file and wants no recovery copy of its
        // own: its owner holds it.
        guard (widget as! OfficeShell).hosted == nil else { return }
        #if os(WASI)
        // The browser has no files of ours: only the page's recovery copy.
        guard OfficeHost.browserRecovery != nil else { return }
        #endif
        _autosaveGeneration += 1
        let gen = _autosaveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + OfficeHost.autosaveDelay) { [weak self] in
            guard let self, self._autosaveGeneration == gen else { return }
            self._autosaveNow()
        }
    }

    /// The write itself: the file when AutoSave is on and the document has one, else the recovery copy.
    /// Also what the window's host asks for before it closes the window (OfficeScene.flushPendingSaves).
    private func _autosaveNow() {
        guard session.dirty else { return }
        // In a browser tab: the page keeps the copy (there is no file to save in place).
        if let browser = OfficeHost.browserRecovery {
            guard (widget as! OfficeShell).hosted == nil else { return }
            guard _keptRevision != controller.revision else { return }
            let name = session.path ?? session.title + ".docx"
            if let data = try? DocxFormat.write(controller.document, pageSetup: session.pageSetup) {
                browser.keep("docx", name.pathExtension == "docx" ? name : name.deletingPathExtension + ".docx", data)
                _keptRevision = controller.revision
            }
            return
        }
        #if !os(WASI)
        // AutoSave writes the file itself — never a recovered document,
        // whose on-disk file the user has not yet chosen to replace.
        if session.autoSave, !_recovered, let path = session.path {
            do {
                try OfficeFormats.write(controller.document, to: path, pageSetup: session.pageSetup)
                officeScene.documentSaved?(path)
                _savedRevision = controller.revision
                try? FileManager.default.removeItem(atPath: _recoveryPath(for: path))
                setState { session.dirty = false }
                return
            } catch {
                _flash("AutoSave could not write: \(error)")
                // Fall through: at least the recovery copy.
            }
        }
        let recovery = _recoveryPath(for: session.path)
        if let data = try? DocxFormat.write(controller.document, pageSetup: session.pageSetup) {
            try? data.write(to: URL(fileURLWithPath: recovery), options: .atomic)
        }
        #endif
    }

    /// On open: a recovery copy newer than the file means the last session
    /// ended with unsaved changes — load it and say so.
    private func _recoveryIfNewer(than path: String) -> String? {
        let recovery = _recoveryPath(for: path)
        let fm = FileManager.default
        guard let r = try? fm.attributesOfItem(atPath: recovery)[.modificationDate] as? Date,
              let f = try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date, r > f else { return nil }
        return recovery
    }

    // MARK: Documents

    private func _new() {
        var blank = RichDocument()
        blank.styles = OfficeStyles.sheet
        _autosaveGeneration += 1
        _recovered = false
        _browserHandle = nil
        controller.load(blank)
        session.path = nil
        _savedRevision = controller.revision
        setState {
            session.dirty = false
            session.summary = session.summarize()
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
        let kind = DocumentKind.kind(forPath: path)
        if kind != .document, let onSwitch = (widget as! OfficeShell).onSwitch {
            onSwitch(kind, path)
            return
        }
        do {
            _autosaveGeneration += 1
            var recovery = _recoveryIfNewer(than: path)
            var opened: OpenedDocument
            if let r = recovery, let fromCopy = try? OfficeFormats.read(r) {
                opened = fromCopy
            } else {
                // A copy that does not read (a crash mid-write) never blocks the file.
                if let r = recovery { try? FileManager.default.removeItem(atPath: r) }
                recovery = nil
                opened = try OfficeFormats.read(path)
            }
            controller.load(opened.document)
            session.path = path
            _recovered = recovery != nil
            // A recovered document is unsaved by definition.
            _savedRevision = recovery == nil ? controller.revision : controller.revision - 1
            _remember(path)
            setState {
                // A document that declares no page is on the default one — not on
                // the page of whatever was open before it.
                session.pageSetup = opened.pageSetup ?? .letter
                session.dirty = recovery != nil
                session.summary = session.summarize()
                _backstage = nil
            }
            _flash(recovery != nil
                   ? "Restored unsaved changes to \(path.lastPathComponent) — Save to keep them"
                   : "Opened \(path.lastPathComponent)")
        } catch {
            _flash("Could not open \(path.lastPathComponent): \(error)")
            setState { _backstage = nil }
        }
    }

    /// A file the browser handed over: `name` is what the user will see and
    /// what a save is called; there is no path, and no recovery copy to
    /// look for either.
    private func _open(_ name: String, data: Data, handle: Int? = nil) {
        _rememberInBrowser(name, data, handle: handle)
        // A deck or a workbook: its own shell opens it, from the same bytes.
        let kind = DocumentKind.kind(forPath: name)
        if kind != .document, let onSwitch = (widget as! OfficeShell).onSwitch {
            PickedFile.hand(name, data, handle: handle)
            onSwitch(kind, name)
            return
        }
        do {
            try _open(name, opened: OfficeFormats.read(data, named: name))
            _browserHandle = handle
        } catch {
            _flash("Could not open \(name): \(error)")
        }
    }

    private func _open(_ path: String, opened: OpenedDocument) throws {
        #if os(WASI)
        // Ask the page for the script fonts the text needs before its first
        // layout; the page holds that layout (a few seconds at most) for them.
        for paragraph in opened.document.paragraphs { ScriptFonts.request(for: paragraph.text) }
        #endif
        controller.load(opened.document)
        session.path = path
        _browserHandle = nil
        _savedRevision = controller.revision
        _remember(path)
        setState {
            // A document that declares no page is on the default one — not on
            // the page of whatever was open before it.
            session.pageSetup = opened.pageSetup ?? .letter
            session.dirty = false
            session.summary = session.summarize()
            _backstage = nil
        }
        _flash("Opened \(path.lastPathComponent)")
    }

    private func _save(afterSaving: (() -> Void)? = nil) {
        _leaveBox()
        if let hosted = (widget as! OfficeShell).hosted {
            // The owner stores it (a wiki page: a new version). Export is
            // still the way to a .docx.
            let revision = controller.revision
            hosted.save(controller.document, session.pageSetup) { [weak self] message in
                guard let self, self.mounted else { return }
                if let message {
                    self.setState { self._backstage = nil }
                    self._flash(message)
                    return
                }
                self._savedRevision = revision
                self.setState {
                    self.session.dirty = self.controller.revision != revision
                    self._backstage = nil
                }
                self._flash("Saved to the \(hosted.ownerName)")
                if !self.session.dirty { afterSaving?() }
            }
            return
        }
        if let files = OfficeHost.browserFiles {
            // Back into the file it came from, where the browser gave us its
            // handle; else the browser's save picker; else a download, named
            // after the document (the browser decides where it goes).
            if let handle = _browserHandle, let name = session.path {
                _writeInBrowser(files, handle: handle, name: name, afterSaving: afterSaving)
            } else if files.canPickPlace {
                _saveAsInBrowser(files, afterSaving: afterSaving)
            } else {
                _downloadInBrowser(files, name: session.path ?? session.title + ".docx", afterSaving: afterSaving)
            }
            return
        }
        guard let path = session.path else {
            setState { _backstage = .saveAs }
            return
        }
        _saveTo(path)
    }

    // MARK: Saving in a browser tab

    /// The bytes of the document in the format its name asks for.
    private func _encoded(for name: String) -> Data? {
        do {
            return try OfficeFormats.encode(controller.document, as: name.pathExtension, pageSetup: session.pageSetup)
        } catch {
            _flash("Could not save: \(plainFailure(error))")
            return nil
        }
    }

    /// Save As through the browser's own picker: a place and a name, in one
    /// of the formats Word writes (the document's own first).
    private func _saveAsInBrowser(_ files: OfficeHost.BrowserFiles, afterSaving: (() -> Void)? = nil) {
        _leaveBox()
        let suggested = session.path.map { $0.lastPathComponent } ?? session.title.deletingPathExtension + ".docx"
        let own = suggested.pathExtension.lowercased()
        let kinds = (OfficeFormats.writable.contains(own) ? [own] : []) + OfficeFormats.writable.filter { $0 != own }
        files.pickPlace(suggested, kinds) { [weak self] place in
            guard let self, self.mounted, let place else { return }
            self._writeInBrowser(files, handle: place.handle, name: place.name, afterSaving: afterSaving)
        }
    }

    private func _writeInBrowser(_ files: OfficeHost.BrowserFiles, handle: Int, name: String,
                                 afterSaving: (() -> Void)?) {
        let revision = controller.revision
        guard let data = _encoded(for: name) else { return }
        files.write(handle, data) { [weak self] ok in
            guard let self, self.mounted else { return }
            if ok {
                self._browserSaved(name, data, handle: handle, revision: revision, afterSaving: afterSaving)
            } else {
                self._flash("Could not save \(name): the browser did not allow writing to it")
            }
        }
    }

    private func _downloadInBrowser(_ files: OfficeHost.BrowserFiles, name: String, afterSaving: (() -> Void)? = nil) {
        _leaveBox()
        let revision = controller.revision
        guard let data = _encoded(for: name) else { return }
        files.download(name, data)
        _browserSaved(name, data, handle: nil, revision: revision, afterSaving: afterSaving)
    }

    private func _browserSaved(_ name: String, _ data: Data, handle: Int?, revision: Int, afterSaving: (() -> Void)?) {
        OfficeHost.browserRecovery?.discard()
        _keptRevision = nil
        _rememberInBrowser(name, data, handle: handle)
        _recovered = false
        _autosaveGeneration += 1
        session.path = name
        _browserHandle = handle
        _savedRevision = revision
        setState {
            session.dirty = controller.revision != revision
            _backstage = nil
        }
        _flash(OfficeFormats.losesFormatting(name)
               ? "Saved as plain text — formatting is not kept in .txt"
               : "Saved \(name)")
        if !session.dirty { afterSaving?() }
    }

    private func _saveTo(_ path: String) {
        _leaveBox()
        if let files = OfficeHost.browserFiles {
            // Our own Save As box in a browser without a save picker: a name, then a download.
            _downloadInBrowser(files, name: path.lastPathComponent)
            return
        }
        do {
            try OfficeFormats.write(controller.document, to: path, pageSetup: session.pageSetup)
            officeScene.documentSaved?(path)
            // The recovery copies this document may have left: under its
            // new name, its old name, and the untitled slot if it had no name.
            let fm = FileManager.default
            try? fm.removeItem(atPath: _recoveryPath(for: path))
            if let old = session.path, old != path { try? fm.removeItem(atPath: _recoveryPath(for: old)) }
            if session.path == nil { try? fm.removeItem(atPath: _recoveryPath(for: nil)) }
            OfficeHost.browserRecovery?.discard()
            _keptRevision = nil
            _recovered = false
            _autosaveGeneration += 1
            session.path = path
            _savedRevision = controller.revision
            _remember(path)
            setState {
                session.dirty = false
                _backstage = nil
            }
            _flash(OfficeFormats.losesFormatting(path)
                   ? "Saved as plain text — formatting is not kept in .txt"
                   : "Saved \(path.lastPathComponent)")
        } catch {
            _flash("Could not save: \(plainFailure(error))")
        }
    }

    private func _export(_ ext: String, share: Bool = false) {
        _leaveBox()
        let base = session.path.map { $0.deletingPathExtension }
            ?? homeDirectory() + "/Documents/" + session.title
        let target = base + "." + ext
        #if os(WASI)
        do {
            // A PDF is a download too: the renderer writes it (PdfDocument).
            if ext == "pdf" {
                // (After its pictures are decoded: the browser decodes them
                // only between turns of its event loop.)
                setState { _backstage = nil }
                PdfExport.writeWhenDecoded(controller.document, pageSetup: session.pageSetup, theme: session.theme,
                                           to: target, title: session.title) { [weak self] ok in
                    self?._flash(ok ? "Exported \(target.lastPathComponent)" : "Could not write the PDF")
                }
                return
            }
            let data = try OfficeFormats.encode(controller.document, as: ext, pageSetup: session.pageSetup)
            WebFiles.download(data, as: target.lastPathComponent)
            setState { _backstage = nil }
            _flash("Exported \(target.lastPathComponent)")
        } catch {
            _flash("Could not export: \(error)")
        }
        return
        #endif
        if let ask = share ? officeScene.shareRequested : officeScene.exportRequested {
            setState { _backstage = nil }
            ask(target.lastPathComponent, { [weak self] path, finished in
                guard let self else { finished(false); return }
                if ext == "pdf" {
                    self._outOfThisBlock {
                        finished(PdfExport.write(self.controller.document, pageSetup: self.session.pageSetup,
                                                 theme: self.session.theme, to: path, title: self.session.title))
                    }
                } else {
                    finished((try? OfficeFormats.write(self.controller.document, to: path,
                                                       pageSetup: self.session.pageSetup)) != nil)
                }
            }, false) { [weak self] picked in
                if let picked { self?._flash("\(share ? "Shared" : "Exported") \(picked)") }
            }
            return
        }
        do {
            if ext == "pdf" {
                guard PdfExport.write(controller.document, pageSetup: session.pageSetup, theme: session.theme,
                                      to: target, title: session.title) else {
                    _flash("Could not write the PDF")
                    return
                }
            } else {
                try OfficeFormats.write(controller.document, to: target, pageSetup: session.pageSetup)
            }
            _remember(target)
            setState { _backstage = nil }
            _flash("Exported \(target.lastPathComponent)")
        } catch {
            _flash("Could not export: \(error)")
        }
    }

    /// W-FD-2: a table of contents of the headings, with the page numbers the document lays out to.
    private func _insertContents(_ options: ContentsOptions) {
        let labels = PdfExport.pageLabels(controller.document, pageSetup: session.pageSetup, theme: session.theme)
        if !controller.insertTableOfContents(options, width: session.pageSetup.columnWidth, pageOf: labels, layout: { PdfExport.pageLabels($0, pageSetup: self.session.pageSetup, theme: self.session.theme) }) {
            _flash(options.caption.map { "There are no \($0) captions to list: use References > Insert Caption first" }
                   ?? "There are no headings to list: give a paragraph a Heading style first")
        }
    }

    private func _flash(_ message: String) {
        _statusGeneration += 1
        let gen = _statusGeneration
        setState { _status = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(4)) { [weak self] in
            guard let self, self._statusGeneration == gen else { return }
            self.setState { self._status = nil }
        }
    }

    private func _loadRecent() -> [String] { OfficeHost.browserRecent?.names() ?? OfficeRecent.load() }

    private func _remember(_ path: String) {
        // A tab's list is the page's (its bytes went there with `_rememberInBrowser`).
        if let browser = OfficeHost.browserRecent { _recent = browser.names(); return }
        _recent = OfficeRecent.remember(path, in: _recent)
    }

    /// A document opened or saved in a tab: the page keeps its bytes under its name, so Recent can reopen it.
    private func _rememberInBrowser(_ name: String, _ data: Data, handle: Int?) {
        guard let browser = OfficeHost.browserRecent else { return }
        browser.remember(name, data, handle)
        _recent = browser.names()
    }

    // MARK: Pictures

    /// Decode for the intrinsic size (pixels read as 96/in), then insert.
    /// W-PG-3: a watermark in every header, or none, as one undo step. A picture is read and measured first.
    func _applyWatermark(_ choice: WatermarkChoice) {
        switch choice {
        case .none: _setWatermark(nil)
        case .text(let t): _setWatermark(.text(t))
        case .picture(let path, let scale, let washout):
            guard let data = FileManager.default.contents(atPath: path) else {
                _flash("Could not read \(path.lastPathComponent)")
                return
            }
            let name = path.lastPathComponent
            let ext = name.split(separator: ".").count > 1 ? String(name.split(separator: ".").last!).lowercased() : "png"
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let codec = try await instantiateImageCodec([UInt8](data))
                    let frame = try await codec.getNextFrame()
                    codec.dispose()
                    let px = Double(frame.image.width), py = Double(frame.image.height)
                    frame.image.dispose()
                    self._setWatermark(.picture(WordWatermark.PictureMark(data: data, ext: ext == "jpg" ? "jpeg" : ext, name: name,
                                                                          naturalWidth: px * 0.75, naturalHeight: py * 0.75,
                                                                          scale: scale, washout: washout)))
                } catch {
                    self._flash("\(name) is not a picture this app can read")
                }
            }
        }
    }

    private func _setWatermark(_ mark: WordWatermark?) {
        guard mark != nil || WordWatermark.has(in: controller.document) else { return }
        do {
            let d = try WordWatermark.setting(mark, in: controller.document, page: session.pageSetup)
            setState {
                controller.replaceDocument(with: d)
                session.summary = session.summarize()
            }
        } catch {
            _flash("The watermark could not be set")
        }
    }

    private func _insertPicture(_ path: String) {
        setState { _backstage = nil }
        guard let data = FileManager.default.contents(atPath: path) else {
            _replaceTarget = nil
            _flash("Could not read \(path.lastPathComponent)")
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let codec = try await instantiateImageCodec([UInt8](data))
                let frame = try await codec.getNextFrame()
                codec.dispose()
                let px = Double(frame.image.width), py = Double(frame.image.height)
                frame.image.dispose()
                if let t = self._replaceTarget {
                    self._replaceTarget = nil
                    if self.controller.replacePicture(at: t.index, inline: t.inline, with: data, name: path.lastPathComponent,
                                                      naturalWidth: px * 0.75, naturalHeight: py * 0.75) {
                        self._flash("Changed to \(path.lastPathComponent)")
                    } else { self._flash("This picture cannot be changed") }
                    return
                }
                let maxW = self.session.pageSetup.contentWidth
                var w = px * 0.75, h = py * 0.75
                if w > maxW { h *= maxW / w; w = maxW }
                self.controller.insertImage(ImageAttachment(data: data, width: w, height: h,
                                                            name: path.lastPathComponent,
                                                            naturalWidth: px * 0.75, naturalHeight: py * 0.75))
                self._flash("Inserted \(path.lastPathComponent)")
            } catch {
                self._flash("Not an image Office can decode: \(path.lastPathComponent)")
            }
        }
    }

    // MARK: Find

    private func _openFind(replace: Bool) {
        setState {
            _findOpen = true
            _findReplace = replace
            _findStatus = ""
        }
        if controller.hasSelection, !controller.selectedText.contains(Character("\n")) {
            _findQuery.text = controller.selectedText
        }
        // The query — the selection's, or the last one — comes up selected,
        // so typing a different one replaces it.
        let seed = _findQuery.text
        _findQuery.value = TextEditingValue(text: seed, selection: TextSelection(baseOffset: 0, extentOffset: seed.utf16.count))
    }

    private func _openFindDialog() {
        if controller.hasSelection, !controller.selectedText.contains(Character("\n")) {
            _findQuery.text = controller.selectedText
        }
        setState { _findDialogOpen = true }
    }

    private func _closeFindDialog() {
        setState { _findDialogOpen = false }
        _editorFocus.requestFocus()
    }

    /// What the shared Find and Replace dialog does in Writer (U-FR-1).
    private var _findHooks: FindHooks {
        func select(_ s: RichSelection?, _ p: TextPattern) -> String {
            guard let s else { return "No matches" }
            controller.selection = s
            guard let at = controller.matchPosition(p) else { return "" }
            return "\(at.index) of \(at.total)"
        }
        var hooks = FindHooks(
            findNext: { [unowned self] p, _, back in select(controller.find(p, backwards: back), p) },
            replace: { [unowned self] p, template, _ in
                // Replace the match the caret is on, then move to the next one.
                let replaced = controller.replaceSelection(p, with: template)
                let next = select(controller.find(p), p)
                return replaced ? (next == "No matches" ? "Replaced. No more matches" : "Replaced") : next
            },
            replaceAll: { [unowned self] p, template, _ in
                let n = controller.replaceAll(p, with: template)
                return n == 0 ? "No matches" : "Replaced \(n)"
            })
        hooks.goToLabel = "Go to paragraph"
        hooks.goToHint = "A paragraph number, from 1"
        hooks.goTo = { [unowned self] text in
            guard let n = Int(text.trimmingWhitespace()), n >= 1 else { return "Type a paragraph number" }
            guard n <= controller.document.paragraphs.count else {
                return "The document has \(controller.document.paragraphs.count) paragraphs"
            }
            controller.selection = RichSelection(anchor: RichPosition(paragraph: n - 1, offset: 0),
                                                 focus: RichPosition(paragraph: n - 1, offset: 0))
            return nil
        }
        return hooks
    }

    private func _findNext(backwards: Bool) {
        let q = _findQuery.text
        guard !q.isEmpty else { return }
        if let sel = controller.find(q, backwards: backwards) {
            controller.selection = sel
            setState { _findStatus = "" }
            if let at = (try? TextPattern(q, FindOptions())).flatMap({ controller.matchPosition($0) }) { ScreenReader.announce("\(at.index) of \(at.total)") }
        } else {
            setState { _findStatus = "No matches" }
            ScreenReader.announce("No matches")
        }
    }

    private func _replaceOne() {
        let q = _findQuery.text
        guard !q.isEmpty else { return }
        if controller.hasSelection,
           controller.selectedText.lowercased() == q.lowercased() {
            controller.insertText(_findReplacement.text)
        }
        _findNext(backwards: false)
    }

    private func _replaceAll() {
        let n = controller.replaceAll(_findQuery.text, with: _findReplacement.text)
        setState { _findStatus = n == 0 ? "No matches" : "Replaced \(n)" }
    }

    // MARK: Clipboard and the context menu

    /// The misspelled word the caret is in or the selection is (all of it, or part), if spelling is checked and it is one.
    private func _misspelledWord() -> (paragraph: Int, range: Range<Int>, word: String)? {
        let c = controller
        let sel = c.selection
        guard let checker = _spelling, session.checkSpelling, !c.readOnly, sel.anchor.paragraph == sel.focus.paragraph,
              sel.focus.paragraph < c.document.paragraphs.count else { return nil }
        let text = c.document.paragraphs[sel.focus.paragraph].text
        let lo = min(sel.anchor.offset, sel.focus.offset), hi = max(sel.anchor.offset, sel.focus.offset)
        guard let r = c.document.paragraphs[sel.focus.paragraph].outsideFieldCodes(checker.misspelledRanges(in: text)).first(where: { $0.lowerBound <= lo && hi <= $0.upperBound }) else { return nil }
        return (sel.focus.paragraph, r, _utf16Slice(text, r))
    }

    /// The host's edit menu for a finger's selection or caret (iPad: the system
    /// menu). Nothing happens on a host that draws none.
    private func _showTouchMenu(_ rect: Rect?) {
        // A misspelled word under the caret or selected: its first three corrections lead the menu, as the system's do.
        var leading: [OfficeHost.EditMenuItem] = []
        let c = controller
        if rect != nil, let checker = _spelling, let bad = _misspelledWord() {
            let paragraph = bad.paragraph, r = bad.range, word = bad.word
            for g in checker.suggestions(for: word).prefix(3) {
                leading.append(.init(title: g, symbol: "textformat.abc") { [weak c] in
                    // The menu takes no focus, so the document may have changed under it: replace only the word still there.
                    guard let c, paragraph < c.document.paragraphs.count else { return }
                    let now = c.document.paragraphs[paragraph].text
                    guard r.upperBound <= now.utf16.count, _utf16Slice(now, r) == word else { return }
                    c.replaceText(in: paragraph, r, with: g)
                })
            }
        }
        officeScene.showTouchMenu(rect, controller: controller, leading: leading)
    }

    private func _paste(plain: Bool) { _paste(mode: plain ? .textOnly : .keepSource) }

    private func _paste(mode: RichDocumentController.PasteMode) {
        Clipboard.getData(mode == .textOnly ? Clipboard.kTextPlain : Clipboard.kAll) { [weak self] data in
            guard let self, let data, !data.isEmpty else { return }
            DispatchQueue.main.async { self.controller.paste(data: data, mode: mode) }
        }
    }

    /// The Paste Options button's menu (W-ED-1): the last paste made again another way, in one undo step. While it
    /// is open K, M, U and T pick, as Word's underlined letters do.
    private func _showPasteOptions(at point: Offset) {
        let c = controller
        guard c.pasteOptions != nil, let context else { return }
        let choices: [(String, Character, RichDocumentController.PasteMode)] = [
            ("Keep Source Formatting (K)", "k", .keepSource), ("Merge Formatting (M)", "m", .mergeFormatting),
            ("Picture (U)", "u", .picture), ("Keep Text Only (T)", "t", .textOnly)]
        let menu = ContextMenuBuilder()
        for (label, _, mode) in choices {
            menu.item(label, enabled: c.canRepaste(mode)) { [weak self] in self?._repaste(mode) }
        }
        menu.show(_contextMenu, in: context, at: point)
        if let k = _pasteKeys { FocusManager.instance.removeKeyInterceptor(k) }
        _pasteKeys = FocusManager.instance.addKeyInterceptor { [weak self] key in
            guard let self else { return false }
            guard self._contextMenu.isOpen, self.controller.pasteOptions != nil else { self._endPasteKeys(); return false }
            guard let letter = KeyChordTracker.letter(key.logical),
                  let pick = choices.first(where: { $0.1 == letter }) else { return false }
            if key.type == .down, self.controller.canRepaste(pick.2) { self._repaste(pick.2) }
            return true
        }
    }

    private func _repaste(_ mode: RichDocumentController.PasteMode) {
        _endPasteKeys()
        if _contextMenu.isOpen { _contextMenu.closeFlyout() }
        controller.repaste(mode)
    }

    /// Paste Special: reads the whole clipboard, then asks which format to paste.
    private func _openPasteSpecial() {
        Clipboard.getData(Clipboard.kAll) { [weak self] data in
            DispatchQueue.main.async {
                guard let self, self.mounted else { return }
                let data = data ?? ClipboardData(text: nil)
                self.setState { self._pasteSpecialData = data }
            }
        }
    }

    private func _endPasteKeys() {
        if let k = _pasteKeys { FocusManager.instance.removeKeyInterceptor(k); _pasteKeys = nil }
    }

    /// Word's right-click menu: what the caret is on, then the clipboard,
    /// then formatting, then the table or picture it sits in.
    private func _showContextMenu(at point: Offset) {
        let c = controller
        let menu = ContextMenuBuilder()
        func item(_ text: String, enabled: Bool = true, _ action: @escaping () -> Void) { menu.item(text, enabled: enabled, action) }
        func sep() { menu.separator() }
        // A misspelled word under the click: its corrections first, as Word.
        if let checker = _spelling, let bad = _misspelledWord() {
            let pos = (paragraph: bad.paragraph, offset: bad.range.lowerBound)
            do {
                let r = bad.range, word = bad.word
                let guesses = checker.suggestions(for: word).prefix(5)
                if guesses.isEmpty {
                    item("(No Spelling Suggestions)", enabled: false) {}
                }
                for g in guesses {
                    item(g) { [weak self] in
                        // The menu takes no focus, so the document may have
                        // changed under it: replace only the word still there.
                        guard pos.paragraph < c.document.paragraphs.count else { return }
                        let now = c.document.paragraphs[pos.paragraph].text
                        guard r.upperBound <= now.utf16.count, _utf16Slice(now, r) == word else { return }
                        c.replaceText(in: pos.paragraph, r, with: g)
                        self?._flash("Corrected to “\(g)”")
                    }
                }
                sep()
                // The layout re-reads the checker's version on its next paint;
                // a repaint is all that is needed, not a fresh layout.
                item("Ignore All") { [weak self] in checker.ignore(word); self?.controller.notifyListeners() }
                item("Add to Dictionary") { [weak self] in checker.learn(word); self?.controller.notifyListeners() }
                sep()
            }
        }
        if let link = c.currentLink {
            item("Open Link") { [weak self] in self?._followLink(link) }
            item("Edit Link…") { [weak self] in self?._openLink() }
            item("Remove Link") { c.setLink(nil) }
            sep()
        }
        // A list item: Word's numbering commands, as on its right-click menu.
        if c.isNumberedItem {
            item("Restart at 1") { c.restartNumbering() }
            item("Continue Numbering", enabled: c.canContinueNumbering) { c.continueNumbering() }
            item("Set Numbering Value…") { [weak self] in self?.session.onNumberingValueDialog?() }
            sep()
        }
        let has = c.hasSelection
        item("Cut", enabled: has) { if let d = c.cutSelectionData() { Clipboard.setData(d) } }
        item("Copy", enabled: has) { if let d = c.copySelectionData() { Clipboard.setData(d) } }
        item("Paste") { [weak self] in self?._paste(plain: false) }
        item("Paste: Merge Formatting") { [weak self] in self?._paste(mode: .mergeFormatting) }
        item("Paste: Keep Text Only") { [weak self] in self?._paste(mode: .textOnly) }
        item("Paste: Picture") { [weak self] in self?._paste(mode: .picture) }
        sep()
        menu.miniButton(FluentSystemIcons.textBold, "Bold", on: c.selectionAll { $0.bold }) { c.toggleBold() }
        menu.miniButton(FluentSystemIcons.textItalic, "Italic", on: c.selectionAll { $0.italic }) { c.toggleItalic() }
        menu.miniButton(FluentSystemIcons.textUnderline, "Underline", on: c.selectionAll { $0.underline }) { c.toggleUnderline() }
        if c.currentLink == nil { item("Link…") { [weak self] in self?._openLink() } }
        if let i = c.selectedImageIndex, let image = c.document.paragraphs[i].image {
            sep()
            item("Fit Picture to Width") { [weak self] in
                guard let self else { return }
                let w = self.session.pageSetup.columnWidth
                c.setImageSize(at: i, width: w, height: w * image.height / max(1, image.width))
            }
            item("Original Size", enabled: image.naturalWidth != nil) {
                if let nw = image.naturalWidth, let nh = image.naturalHeight { c.setImageSize(at: i, width: nw, height: nh) }
            }
            item(c.pictureAspectLock ? "Unlock Aspect Ratio" : "Lock Aspect Ratio") { [weak self] in self?.session.onToggleAspectLock?() }
            item("Delete Picture") { c.deleteForward() }
        }
        if c.isInCell {
            sep()
            item("Insert Row Above") { c.insertRow(below: false) }
            item("Insert Row Below") { c.insertRow(below: true) }
            item("Insert Column Left") { c.insertColumn(after: false) }
            item("Insert Column Right") { c.insertColumn(after: true) }
            item("Delete Row") { c.deleteRow() }
            item("Delete Column") { c.deleteColumn() }
            if c.selection.block != nil || c.selectedCellsInRow.count > 1 || c.selectedCellsInColumn.count > 1 { item("Merge Cells") { c.mergeCells() } }
            if let cell = c.currentCell, cell.span > 1 || cell.rowSpan > 1 { item("Split Cell") { c.splitCell() } }
            item("Delete Table") { c.deleteTable() }
        }
        sep()
        item("Select All") { c.selectAll() }
        guard let context else { return }
        menu.show(_contextMenu, in: context, at: point)
    }

    // MARK: Links

    private func _openLink() {
        setState { _linkDialogOpen = true }
    }

    private var _linkHooks: HyperlinkHooks {
        let targets = controller.linkTargets()
        let places = targets.enumerated().map { i, t in
            HyperlinkPlace(id: "\(i)", title: t.title,
                           kind: t.kind == .bookmark ? "Bookmark" : "Heading \(t.level)")
        }
        var h = HyperlinkHooks(apply: { [weak self] addr, place, text, tip in
            guard let self else { return "" }
            let target = place.flatMap { Int($0) }.flatMap { $0 < targets.count ? targets[$0] : nil }
            guard self.controller.applyHyperlink(address: addr, target: target, text: text, tip: tip) else { return "Nothing to link to" }
            self._flash("Linked")
            return ""
        })
        h.places = targets.isEmpty ? [] : places
        h.address = controller.currentLink ?? ""
        h.displayText = controller.selectedText
        h.tip = controller.currentLinkTip ?? ""
        h.canRemove = controller.currentLink != nil
        h.remove = { [weak self] in self?.controller.setLink(nil) }
        return h
    }

    private func _openNote(_ n: NoteReference, box: Rect? = nil) {
        _noteText.text = controller.editableNoteText(n) ?? ""
        if controller.editableNoteText(n) == nil { _flash("This note holds formatting, a link or a picture; edit it in Word."); return }
        if let k = _noteKeys { FocusManager.instance.removeKeyInterceptor(k) }
        // Escape keeps the text and goes back to the page.
        _noteKeys = FocusManager.instance.addKeyInterceptor { [weak self] key in
            guard let self, self._noteOpen != nil, key.type == .down, key.logical == 0x1_0000_001B || key.logical == 0xFF1B else { return false }
            self._commitNote()
            return true
        }
        setState { _noteOpen = n; _noteBox = box ?? Rect.fromLTWH(120, 200, 480, 60) }
        ScreenReader.announce("Editing note. Escape to finish.", priority: .assertive)
    }

    private func _commitNote() {
        if let n = _noteOpen { controller.setNoteText(n, _noteText.text) }
        _closeNote()
    }

    private func _closeNote() {
        if let k = _noteKeys { FocusManager.instance.removeKeyInterceptor(k) }
        _noteKeys = nil
        setState { _noteOpen = nil }
        ScreenReader.announce("Note saved")
        _editorFocus.requestFocus()
    }

    // MARK: Comment card

    /// A click on a comment's balloon: its card, to edit its text in place, reply, resolve or reopen, or delete it.
    func _openCommentCard(_ id: String, box: Rect) {
        guard !controller.readOnly, let t = controller.commentThread(id) else { return }
        _cardText.text = t.comment.text
        _replyText.text = ""
        if let k = _cardKeys { FocusManager.instance.removeKeyInterceptor(k) }
        // Escape keeps what was typed and goes back to the page.
        _cardKeys = FocusManager.instance.addKeyInterceptor { [weak self] key in
            guard let self, self._cardOpen != nil, key.type == .down, key.logical == 0x1_0000_001B || key.logical == 0xFF1B else { return false }
            self._commitCommentCard()
            return true
        }
        controller.breakUndoCoalescing()
        setState { _cardOpen = t.comment.id; _cardBox = box }
        ScreenReader.announce("Comment by \(t.comment.author). Escape to finish.", priority: .assertive)
    }

    /// Keeps the card's edits: the comment's new text, and a reply when one was typed.
    func _commitCommentCard() {
        if let id = _cardOpen, let t = controller.commentThread(id) {
            if _cardText.text != t.comment.text { controller.setCommentText(id, _cardText.text) }
            if !_replyText.text.isEmpty { controller.replyToComment(id, text: _replyText.text) }
        }
        _closeCommentCard()
    }

    private func _closeCommentCard() {
        if let k = _cardKeys { FocusManager.instance.removeKeyInterceptor(k) }
        _cardKeys = nil
        setState { _cardOpen = nil }
        controller.invalidateLayout()
        _editorFocus.requestFocus()
    }

    /// The comment card is a white paper card in the margin whatever the app theme: its buttons and text boxes take a light
    /// theme (with the app's accent) so labels are dark on white, not the dark theme's pale text on a white card (job 71).
    static func commentCardTheme(_ fluent: FluentThemeData) -> FluentThemeData {
        FluentThemeData(brightness: .light, accentColor: fluent.accentColor)
    }

    private func _commentCard(_ id: String, _ fluent: FluentThemeData) -> Widget {
        guard let t = controller.commentThread(id) else { return SizedBox(width: 0, height: 0) }
        let px = 96.0 / 72 * session.zoom
        let ink = Color(0xFF1B1B1B)
        func name(_ c: RichDocumentController.DocComment) -> String { c.author.isEmpty ? "Comment" : c.author }
        func box(_ key: String, _ c: TextEditingController, _ lines: Int, _ focus: Bool, _ hint: String) -> Widget {
            CardKeyed(key, FluentTextBox(controller: c, placeholderText: hint, maxLines: lines,
                style: TextStyle(color: ink, fontSize: 9 * px), autofocus: focus))
        }
        var rows: [Widget] = [Text(name(t.comment), style: TextStyle(color: ink, fontSize: 9 * px, fontWeight: .bold)),
                              box("comment-text", _cardText, 6, true, "Comment")]
        for r in t.replies {
            rows.append(Padding(padding: EdgeInsets(left: 8, top: 6, right: 0, bottom: 0), child: Column(crossAxisAlignment: .start, children: [
                Text(name(r), style: TextStyle(color: ink, fontSize: 8 * px, fontWeight: .bold)),
                Text(r.text, style: TextStyle(color: ink, fontSize: 8 * px)),
            ])))
        }
        rows.append(SizedBox(height: 6))
        rows.append(box("comment-reply", _replyText, 3, false, "Reply"))
        rows.append(SizedBox(height: 6))
        func button(_ key: String, _ label: String, _ action: @escaping () -> Void) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 6, bottom: 0),
                    child: CardKeyed(key, FlatButton(
                        child: Padding(padding: EdgeInsets(left: 6, top: 0, right: 6, bottom: 0),
                                       child: Text(label, style: TextStyle(color: ink, fontSize: 9 * px))), width: nil, action: action)))
        }
        rows.append(Row(children: [
            button("comment-post", "Reply") { [weak self] in self?._commitCommentCard() },
            button("comment-resolve", t.comment.done ? "Reopen" : "Resolve") { [weak self] in
                guard let self else { return }
                self._commitCommentCard()
                self.controller.setCommentResolved(id, !t.comment.done)
                self.session.onStatus?(t.comment.done ? "Comment reopened" : "Comment resolved")
            },
            button("comment-delete", "Delete") { [weak self] in
                guard let self else { return }
                self.controller.deleteComment(id)
                self._closeCommentCard()
                self.session.onStatus?("Comment deleted")
            },
        ]))
        return DecoratedBox(decoration: BoxDecoration(color: Color(0xFFFFFFFF), border: Border.all(color: Color(0xFF2B579A), width: 1.5),
                                                      borderRadius: BorderRadius.circular(4)),
                            child: Padding(padding: EdgeInsets(all: 8),
                                child: FluentTheme(data: Self.commentCardTheme(fluent),
                                    child: KeyboardRegion(name: "Comment", modal: true, child: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: rows)))))
    }

    // MARK: Shortcuts

    func _cancelPainter() {
        session.paintedStyle = nil
        session.paintSticky = false
        _flash("Format Painter off")
        setState { session.summary = session.summarize() }
    }

    /// Paint the selection (a bare click paints its word) and drop the
    /// painter unless it was double-clicked on.
    func _applyPainter() {
        guard let painted = session.paintedStyle else { return }
        controller.selectWordForPainting()
        guard controller.hasSelection else { return }
        if !session.paintSticky { session.paintedStyle = nil }
        controller.pasteFormat(painted)
        _flash("Painted")
        setState { session.summary = session.summarize() }
    }

    /// F9 (`everywhere` false): the fields in the selection, or the one at the caret, brought up to date. The ribbon's
    /// Update Fields (`everywhere`): every field when nothing is selected.
    @discardableResult
    func _updateFields(everywhere: Bool) -> Int {
        let info = PdfExport.pageInfo(controller.document, pageSetup: session.pageSetup, theme: session.theme)
        let clock = FieldClock.current()
        let props = FieldEvaluator.properties(keptParts: controller.document.keptParts)
        let n = controller.updateFields(pageOf: info.label, pageCount: info.count, everywhere: everywhere,
                                        other: { [session] in FieldEvaluator.evaluate($0, shown: $1, clock: clock, properties: props, path: session.path) })
        _flash(n == 0 ? "No field here needs updating" : "Fields updated")
        setState { session.summary = session.summarize() }
        return n
    }

    /// Insert → Field: put the field at the caret showing what it evaluates to now. A property the document has not
    /// set (an empty Title) has nothing to show, so nothing is inserted and the message says where to set it.
    func _insertField(_ instruction: String) {
        let c = controller
        let word = instruction.split(separator: " ").first.map(String.init) ?? ""
        let info = PdfExport.pageInfo(c.document, pageSetup: session.pageSetup, theme: session.theme)
        var result: String?
        switch word {
        case "PAGE": result = info.label(c.document.clamped(c.selection.focus).paragraph) ?? "1"
        case "NUMPAGES": result = String(info.count)
        default:
            result = FieldEvaluator.evaluate(instruction, shown: "", clock: FieldClock.current(),
                                             properties: FieldEvaluator.properties(keptParts: c.document.keptParts), path: session.path)
        }
        guard let result, !result.isEmpty else {
            _flash(word == "FILENAME" ? "Save the document first: it has no file name yet"
                                      : "The document has no \(word.lowercased()) yet: set it in File > Info")
            return
        }
        c.insertField(instruction, result: result)
        setState { session.summary = session.summarize() }
    }

    func _shortcut(_ key: KeyData, _ mods: KeyModifiers) -> Bool {
        let named = KeyChordTracker.named(key.logical)
        if named == .escape {
            if _boxEdit != nil { _leaveBox(); return true }
            if session.paintedStyle != nil { _cancelPainter(); return true }
            if _styleOpen != nil { setState { _styleOpen = nil }; return true }
            if _shortcutsOpen { return false }   // the dialog's own Esc closes it
            if LinkCard.link(caret: _cardLink, hover: _hoverCard, dismissed: _cardDismissed) != nil { setState { _cardDismissed = true }; return true }
            if _listSymbolPick != nil { setState { _listSymbolPick = nil }; return true }
            if _paragraphOpen || _tablePropsOpen || _fontOpen || _insertTableOpen || _splitCellOpen || _contentsOpen || _noteOptionsOpen || _convertTextTable != nil || _formulaOpen || _sortTable != nil || _bordersOpen || _pictureDialog != nil || _linkDialogOpen || _numberingValueOpen || _multilevelOpen || _commentOpen || _dateTimeOpen || _fieldOpen || _bookmarkOpen || _crossReferenceOpen || _captionOpen || _pageDesign != nil || _propertiesOpen || _listFormatOpen != nil || _newStyleOpen || _pasteSpecialData != nil { return false }   // the dialog's own Esc closes it
            if _headerFooterOpen { setState { _headerFooterOpen = false }; return true }
            if _findOpen { setState { _findOpen = false }; _editorFocus.requestFocus(); return true }
            if _backstage != nil { setState { _backstage = nil }; return true }
            // With nothing else to dismiss, Escape leaves Read Mode.
            if session.viewMode == .readMode { session.onViewMode?(.printLayout); return true }
            return false
        }
        // F9 brings the fields in the selection (or at the caret) up to date.
        if named == .function(9), !_dateTimeOpen, !_fieldOpen, !mods.contains(.shift), !mods.contains(.alt), !mods.contains(.primary) {
            // In a table of contents F9 brings the whole table up to date (new and renamed headings, page numbers).
            if controller.contentsRange(containing: controller.document.clamped(controller.selection.end).paragraph) != nil {
                session.onUpdateContents?(false)
                return true
            }
            _updateFields(everywhere: false)
            return true
        }
        // Alt+Shift+P puts a page-number field at the caret.
        if KeyChordTracker.letter(key.logical) == "p", mods.contains(.alt), mods.contains(.shift), !mods.contains(.primary) {
            let info = PdfExport.pageInfo(controller.document, pageSetup: session.pageSetup, theme: session.theme)
            controller.insertField(" PAGE ", result: info.label(controller.document.clamped(controller.selection.focus).paragraph) ?? "1")
            return true
        }
        // Ctrl+Shift+F5: Insert > Bookmark.
        if named == .function(5), mods.contains(.primary), mods.contains(.shift), !mods.contains(.alt) {
            session.onBookmarkDialog?()
            return true
        }
        // Ctrl+Shift+F9 turns the fields in the selection (or at the caret) into plain text.
        if named == .function(9), mods.contains(.primary), mods.contains(.shift), !mods.contains(.alt) {
            if controller.unlinkFields() == 0 { _flash("No field here to unlink") }
            return true
        }
        // Shift+F9 shows or hides the field code at the caret; Alt+F9 all of them.
        if named == .function(9), !mods.contains(.primary), mods.contains(.shift) || mods.contains(.alt) {
            controller.toggleFieldCodes(all: mods.contains(.alt))
            return true
        }
        guard mods.contains(.primary) else { return false }
        let c = controller
        guard let letter = KeyChordTracker.letter(key.logical) else {
            // ⌥⌘1/2/3 headings and ⌥⌘0 Normal, as in Word.
            if mods.contains(.alt), key.logical >= 0x30, key.logical <= 0x33 {
                c.setHeading(key.logical == 0x30 ? nil : Int(key.logical - 0x30))
                return true
            }
            // ⌘⇧8 Show/Hide ¶ (a digit, so not a letter).
            if mods.contains(.shift), key.logical == 0x38 || key.logical == 0x2A { session.onToggleMarks?(); return true }
            // ⌘= / ⌘- / ⌘0 zoom; ⌘] / ⌘[ grow and shrink the font.
            if key.logical == 0x3D || key.logical == 0x2B { session.onZoom?(session.zoom + 0.1); return true }
            if key.logical == 0x2F { session.onShortcuts?(); return true }   // ⌘/ the shortcut list
            if key.logical == 0x2D { session.onZoom?(session.zoom - 0.1); return true }
            if key.logical == 0x30 { session.onZoom?(1.0); return true }
            // ⌘1 / ⌘2 / ⌘5: single, double and 1.5 line spacing, as Word's Ctrl+1/2/5.
            if !mods.contains(.shift), key.logical == 0x31 || key.logical == 0x32 || key.logical == 0x35 {
                c.setLineSpacing(key.logical == 0x31 ? 1 : key.logical == 0x32 ? 2 : 1.5)
                return true
            }
            if key.logical == 0x5D { c.stepFontSize(1, base: session.effectiveFontSize); return true }
            if key.logical == 0x5B { c.stepFontSize(-1, base: session.effectiveFontSize); return true }
            return false
        }
        // ⌥⌘V (Ctrl+Alt+V in Word) is Paste Special (W-ED-1); ⇧⌘V is the Format Painter's paste (W-P0-5).
        if letter == "v", PasteChord.of(shift: mods.contains(.shift), alt: mods.contains(.alt)) == .pasteSpecial { _openPasteSpecial(); return true }
        // Alt+Ctrl+F inserts a footnote and Alt+Ctrl+D an endnote, as in Word.
        if mods.contains(.alt), !mods.contains(.shift), letter == "f" || letter == "d" {
            session.onInsertNote?(letter == "f" ? .footnote : .endnote)
            return true
        }
        // New Comment, as in Word: Ctrl+Alt+M, and on the Mac Cmd+Option+A.
        #if os(macOS) || os(iOS)
        let newComment: Character = "a"
        #else
        let newComment: Character = "m"
        #endif
        if mods.contains(.alt), !mods.contains(.shift), letter == newComment { session.onNewComment?(); return true }
        // Alt+Ctrl+Shift+S opens and closes the Styles pane, as in Word.
        if mods.contains(.alt), mods.contains(.shift), letter == "s" { session.onToggleStyles?(); return true }
        if mods.contains(.alt) { return false }
        switch letter {
        case "s":
            if mods.contains(.shift) { session.onSaveAs?() } else { _save() }
        case "o": session.onOpen?()
        case "n": session.replacing { [weak self] in self?._new() }
        case "f": _openFind(replace: false)
        case "h": if mods.contains(.shift) { _openFindDialog() } else { _openFind(replace: true) }
        case "g": _findNext(backwards: mods.contains(.shift))
        case "p": session.onPrint?()
        // Word's Ctrl+Shift+K / A / D: small caps, all caps, double underline (ahead of ⌘K the link, ⌘D the Font dialog
        // and the editor's ⌘A, which would otherwise take the shifted keys too).
        case "k" where mods.contains(.shift): c.toggleSmallCaps()
        case "a" where mods.contains(.shift): c.toggleAllCaps()
        case "d" where mods.contains(.shift): c.toggleDoubleUnderline()
        case "k": _openLink()
        case "d": session.onFontDialog?()   // ⌘D: the Font dialog, as in Word
        case "c" where mods.contains(.shift): session.paintedStyle = c.copyFormat(); session.paintSticky = false; setState { session.summary = session.summarize() }
        case "v" where mods.contains(.shift): c.pasteFormat(session.paintedStyle ?? c.copyFormat()); setState { session.summary = session.summarize() }
        // Word's alignment keys; Export lives in Backstage.
        case "e" where mods.contains(.shift): session.onToggleTrackChanges?()   // ⌘⇧E: Track Changes, as Word's Ctrl+Shift+E
        case "e": c.setAlignment(.center)
        case "l" where mods.contains(.shift): c.toggleList(.bullet)   // ⌘⇧L: bullets, as in Word
        case "l": c.setAlignment(.left)
        case "r": c.setAlignment(.right)
        case "j": c.setAlignment(.justify)
        // Word's indent keys: ⌘M / ⌘⇧M move the left indent a default tab stop in or out, ⌘T / ⌘⇧T hang the paragraph.
        case "m": c.stepIndent(forward: !mods.contains(.shift), hanging: false)
        case "t": c.stepIndent(forward: !mods.contains(.shift), hanging: true)
        default: return false
        }
        return true
    }

    // MARK: Build

    private var _windowTitle = ""

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let title = "\(session.title)\(session.dirty ? " •" : "") — Writer"
        if title != _windowTitle {
            _windowTitle = title
            hostSetWindowTitle?(title)
        }
        var column: [Widget] = [
            TitleRow(session: session, searchController: _search, onSearch: { [weak self] q in
                guard let self else { return }
                self._findQuery.text = q
                self._openFind(replace: false)
                self._findNext(backwards: false)
            }),
        ]
        if session.viewMode != .readMode || !_ribbonCollapsed {
            // A picture/shape tab with no image selected (typing into a box swaps the controller) shows Home, not an empty body.
            let shownTab: RibbonTab = (_tab == .pictureFormat || _tab == .shapeFormat) && session.summary.imageIndex == nil && session.deck == nil ? .home : _tab
            column.append(Ribbon(session: session, tab: shownTab, collapsed: _ribbonCollapsed,
                                 onTab: { [weak self] t in self?.setState { self?._tab = t } },
                                 onCollapse: { [weak self] in self?.setState { self?._ribbonCollapsed.toggle() } }))
        }
        if _findOpen {
            column.append(FindBar(session: session, query: _findQuery, replacement: _findReplacement,
                                  showReplace: _findReplace, status: _findStatus,
                                  onNext: { [weak self] back in self?._findNext(backwards: back) },
                                  onReplace: { [weak self] in self?._replaceOne() },
                                  onReplaceAll: { [weak self] in self?._replaceAll() },
                                  onAdvanced: { [weak self] in self?._openFindDialog() },
                                  onClose: { [weak self] in
                                      // (A field being torn down blurs too: once is enough.)
                                      guard let self, self._findOpen else { return }
                                      self.setState { self._findOpen = false }
                                      self._editorFocus.requestFocus()
                                  }))
        }
        if let styleId = _styleOpen {
            column.append(StyleBar(session: session, styleId: styleId,
                                   onClose: { [weak self] in
                                       guard let self else { return }
                                       self.controller.breakUndoCoalescing()
                                       self.setState { self._styleOpen = nil }
                                   }))
        }
        if _colorOpen {
            column.append(ColorBar(hex: _colorText,
                                   onPick: { [weak self] color in
                                       guard let self else { return }
                                       self.controller.setTextColor(color)
                                       self.setState { self._colorOpen = false }
                                   },
                                   onApplyHex: { [weak self] in
                                       guard let self else { return }
                                       guard let color = ColorBar.parse(self._colorText.text) else {
                                           self._flash("Enter a colour as #RRGGBB"); return
                                       }
                                       self.controller.setTextColor(color)
                                       self.setState { self._colorOpen = false }
                                   },
                                   onClose: { [weak self] in self?.setState { self?._colorOpen = false } }))
        }
        if let link = LinkCard.link(caret: _cardLink, hover: _hoverCard, dismissed: _cardDismissed) {
            column.append(LinkCard(
                address: link, tip: link == _cardLink ? (controller.currentLinkTip ?? "") : "",
                onOpen: { [weak self] in self?._followLink(link) },
                onEdit: { [weak self] in self?._openLink() },
                onRemove: { [weak self] in
                    self?.controller.setLink(nil)
                    self?._editorFocus.requestFocus()
                },
                onClose: { [weak self] in self?.setState { self?._cardDismissed = true } }))
        }
        if _headerFooterOpen {
            column.append(HeaderFooterBar(session: session, header: _headerText, footer: _footerText,
                                          headerLocked: controller.document.hasRichHeaderFooter(.header),
                                          footerLocked: controller.document.hasRichHeaderFooter(.footer),
                                          headerLook: _headerLook, footerLook: _footerLook,
                                          onLook: { [weak self] isHeader, look in
                                              self?.setState { if isHeader { self?._headerLook = look } else { self?._footerLook = look } }
                                          },
                                          onApply: { [weak self] in self?._applyHeaderFooterStrip() },
                                          onClose: { [weak self] in self?.setState { self?._headerFooterOpen = false } }))
        }
        // The document column: ruler over the pages, beside the navigation
        // pane when it is open.
        var pages: [Widget] = []
        if session.showRuler && session.viewMode == .printLayout {
            pages.append(Ruler(setup: session.pageSetup, zoom: session.zoom,
                               pixelsPerPoint: session.theme.pixelsPerPoint, sidePadding: 24,
                               style: controller.currentParagraphStyle,
                               onFormat: { [weak self] f in self?.controller.setParagraphFormat(f) }))
        }
        pages.append(Expanded(child: KeyboardPage(focus: { [weak self] in self?._editorFocus.requestFocus() }, child: _pageArea(fluent))))
        var area: [Widget] = []
        var sidePanes: [Widget] = []
        if session.showNavigation {
            sidePanes.append(NavigationPane(session: session, onClose: { [session] in session.onToggleNavigation?() }))
        }
        if session.showStyles {
            sidePanes.append(StylesPane(session: session,
                                        onModify: { [weak self] id in self?.session.onModifyStyle?(id) },
                                        onClose: { [session] in session.onToggleStyles?() }))
        }
        // The chart's data, while a chart is selected.
        var chartPane: Widget? = nil
        if _chartData, let (image, _) = session.wordChart {
            let c = session.controller
            chartPane = ChartDataPane(key: ValueKey("word chart data \(image.id)"),
                                      chart: { WriterCharts.chart(image.id) },
                                      set: { chart, cell in
                                          WordChartEdit.set(chart, of: image, in: c, label: "Edit Data",
                                                            coalesce: cell.map { "chart \(image.id) \($0)" })
                                      },
                                      onClose: { [weak self] in self?.setState { self?._chartData = false } })
            sidePanes.append(chartPane!)
        }
        if _narrow, let pane = sidePanes.last {
            // A side pane beside the page would leave a narrow window (Split View) no page: the newest is a sheet along
            // the bottom instead, full width, with the page above it. (A pane fills the width it is given.)
            column.append(Expanded(child: Column(crossAxisAlignment: .stretch, children: [
                Expanded(flex: 5, child: Column(crossAxisAlignment: .stretch, children: pages)),
                Expanded(flex: 4, child: DecoratedBox(
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: fluent.resources.controlStrokeColorDefault, width: 1))),
                    child: pane)),
            ])))
        } else {
            if session.showNavigation, let nav = sidePanes.first { area.append(nav) }
            area.append(Expanded(child: Column(crossAxisAlignment: .stretch, children: pages)))
            if let chartPane {
                area.append(chartPane)
                column.append(Expanded(child: Row(crossAxisAlignment: .stretch, children: area)))
            } else if session.showStyles, let styles = sidePanes.last {
                // On a touch device the Styles pane floats over the page's right edge (the Navigation pane stays docked on the left).
                if PaneArrangement.isTouchDevice {
                    column.append(Expanded(child: PaneArrangement.arrange(
                        style: .slideOver, fluent: fluent,
                        document: Expanded(child: Row(crossAxisAlignment: .stretch, children: area)), docked: [], newest: styles)))
                } else {
                    area.append(styles)
                    column.append(Expanded(child: Row(crossAxisAlignment: .stretch, children: area)))
                }
            } else {
                column.append(Expanded(child: Row(crossAxisAlignment: .stretch, children: area)))
            }
        }
        column.append(StatusBar(session: session, message: _status ?? _linkHover.map { "⌘-click to open \($0)".keys }))

        let window = SizeReporter(onSize: { [weak self] size in
            guard let self, self.mounted, (size.width < Self.narrowBelow) != self._narrow else { return }
            self.setState { self._narrow = size.width < Self.narrowBelow }
        }, child: ColoredBox(color: fluent.scaffoldBackgroundColor,
                             child: Column(crossAxisAlignment: .stretch, children: column)))
        if _findDialogOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: FindReplaceDialog(
                    initialQuery: _findQuery.text, hooks: _findHooks, onClose: { [weak self] in self?._closeFindDialog() })),
            ])
        }
        if _symbolOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SymbolPicker(
                    hooks: SymbolHooks(
                        fonts: ["(current font)"] + OfficeFonts.families(including: controller.currentCharStyle.fontFamily ?? OfficeFonts.defaultFamily),
                        insert: { [weak self] text, font in self?.controller.insertSymbol(text, font: font) }),
                    onClose: { [weak self] in
                        self?.setState { self?._symbolOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _fontOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: FontDialog(
                    initial: RichDocumentController.CharFormat(controller.currentCharStyle),
                    onOK: { [weak self] f in
                        guard let self else { return }
                        self.controller.setCharFormat(f)
                        self.setState { self._fontOpen = false }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._fontOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _printOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: PrintDialog(
                    hooks: _printHooks,
                    onClose: { [weak self] in
                        self?.setState { self?._printOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if let card = _cardOpen {
            // The comment is edited in its balloon: a card over it. Escape or a click outside keeps the text.
            let box = _cardBox
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Listener(
                    onPointerDown: { [weak self] _ in self?._commitCommentCard() }, behavior: .translucent, child: SizedBox(expand: ()))),
                Positioned(left: box.left, top: box.top, child: SizedBox(width: max(box.width, 240),
                    child: _commentCard(card, FluentTheme.of(context)))),
            ])
        }
        if let note = _noteOpen {
            // The note is edited where it sits on the page: a box over it. Escape or a click outside keeps the text.
            let box = _noteBox
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Listener(
                    onPointerDown: { [weak self] _ in self?._commitNote() }, behavior: .translucent, child: SizedBox(expand: ()))),
                Positioned(left: box.left, top: box.top, child: SizedBox(width: max(box.width, 240),
                    child: KeyboardRegion(name: "Note", modal: true, child: FluentTextBox(controller: _noteText, maxLines: 8,
                        style: TextStyle(color: Color(0xFF000000), fontSize: 10 * 96 / 72 * session.zoom),
                        padding: EdgeInsets.zero,
                        decoration: BoxDecoration(color: Color(0xFFFFFFFF)), focusedDecoration: BoxDecoration(color: Color(0xFFFFFFFF)),
                        showFocusRing: false, autofocus: true)))),
            ])
        }
        if _columnsOpen {
            let sections = controller.document.paragraphs.filter { $0.cell == nil && $0.style.sectionPage != nil }.count + 1
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ColumnsDialog(
                    initial: session.sectionSetup(), sectionCount: sections,
                    onOK: { [weak self] v in
                        guard let self else { return }
                        self.setState {
                            self.controller.changePageSetup(allSections: v.allSections, lastSetup: self.session.pageSetup) { v.apply(to: &$0) }
                            self.session.syncPageSetup()
                            self._columnsOpen = false
                        }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._columnsOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _pageSetupOpen {
            let sections = controller.document.paragraphs.filter { $0.cell == nil && $0.style.sectionPage != nil }.count + 1
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: PageSetupDialog(
                    initial: session.sectionSetup(), sectionCount: sections,
                    options: controller.pageOptions(sectionMark: controller.sectionMark(containing: controller.selection.focus.paragraph)),
                    mirrorMargins: controller.mirrorMargins,
                    onOK: { [weak self] v in
                        guard let self else { return }
                        self.setState {
                            // (One undo step for the whole dialog.)
                            self.controller.edit {
                                self.controller.changePageSetup(allSections: v.allSections, lastSetup: self.session.pageSetup) { v.apply(to: &$0) }
                                self.controller.changePageOptions(allSections: v.allSections, v.options, lastSetup: self.session.pageSetup)
                                self.controller.setMirrorMargins(v.mirror)
                            }
                            self.session.syncPageSetup()
                            self._pageSetupOpen = false
                        }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._pageSetupOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _bordersOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: BordersShadingDialog(
                    onOK: { [weak self] v in
                        guard let self else { return }
                        v.apply(to: self.controller)
                        self.setState { self._bordersOpen = false }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._bordersOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _linkDialogOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: HyperlinkDialog(
                    hooks: _linkHooks,
                    onClose: { [weak self] in
                        self?.setState { self?._linkDialogOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _formulaOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: FormulaDialog(
                    formula: controller.suggestedFormula,
                    preview: { [weak self] f, p in self?.controller.formulaResult(f, picture: p) },
                    onOK: { [weak self] f, p in
                        guard let self else { return }
                        self.controller.insertFormula(f, picture: p)
                        self.setState { self._formulaOpen = false }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._formulaOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if let initial = _sortTable {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SortTableDialog(
                    initial: initial,
                    onOK: { [weak self] v in
                        guard let self else { return }
                        self.controller.sortTable(keys: v.used, headerRow: v.headerRow)
                        self.setState { self._sortTable = nil }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._sortTable = nil }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if let toTable = _convertTextTable {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ConvertTextTableDialog(
                    toTable: toTable,
                    onOK: { [weak self] v in
                        guard let self else { return }
                        if toTable { self.controller.convertTextToTable(separator: v.separator, columns: v.columns) }
                        else { self.controller.convertTableToText(separator: v.separator) }
                        self.setState { self._convertTextTable = nil }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._convertTextTable = nil }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _tablePropsOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: TablePropertiesDialog(
                    initial: TablePropertiesValues(of: controller),
                    onOK: { [weak self] vals in
                        guard let self else { return }
                        vals.apply(to: self.controller)
                        self.setState { self._tablePropsOpen = false }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._tablePropsOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _noteOptionsOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: FootnoteDialog(
                    current: { [weak self] kind in self?.controller.noteOptions(kind) ?? NoteOptions.defaults(kind) },
                    onApply: { [weak self] kind, options in
                        guard let self else { return }
                        self.setState { self._noteOptionsOpen = false }
                        self.controller.setNoteOptions(kind, options)
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._noteOptionsOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _contentsOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ContentsDialog(
                    figureLabels: _figureLabels,
                    onOK: { [weak self] options in
                        guard let self else { return }
                        self.setState { self._contentsOpen = false }
                        self._insertContents(options)
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._contentsOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if let data = _pasteSpecialData {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: WriterPasteSpecialDialog(
                    source: WriterPasteSpecialDialog.sourceLine(data.text), formats: PasteSpecialFormat.offered(by: data),
                    onOK: { [weak self] format in
                        guard let self else { return }
                        self.setState { self._pasteSpecialData = nil }
                        self.controller.pasteSpecial(data, as: format)
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._pasteSpecialData = nil }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _splitCellOpen {
            let cell = controller.currentCell
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SplitCellDialog(
                    columns: max(2, cell?.span ?? 2), rows: cell?.rowSpan ?? 1,
                    merge: controller.selection.block != nil,
                    onOK: { [weak self] n, m, merge in
                        guard let self else { return }
                        if merge { self.controller.mergeCells() }
                        self.controller.splitCell(columns: n, rows: m)
                        self.setState { self._splitCellOpen = false }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._splitCellOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _insertTableOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: InsertTableDialog(
                    onOK: { [weak self] v in
                        guard let self else { return }
                        self.controller.insertTable(rows: v.rows, columns: v.columns, fit: v.fit, textWidth: self.session.pageSetup.contentWidth)
                        self.setState { self._insertTableOpen = false }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._insertTableOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _shortcutsOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ShortcutListDialog(
                    table: ShortcutTable.writer, onClose: { [weak self] in self?.setState { self?._shortcutsOpen = false } })),
            ])
        }
        if let kind = _pictureDialog, let i = session.summary.imageIndex {
            let inline = session.summary.inlineImageID
            let image = inline.map { controller.document.paragraphs[i].inlineImages[$0] } ?? controller.document.paragraphs[i].image
            let close = { [weak self] in
                self?.setState { self?._pictureDialog = nil }
                self?._editorFocus.requestFocus()
            }
            let dialog: Widget = kind == .boxText
                ? PictureAltTextDialog(initial: controller.textBoxText(at: i, inline: inline) ?? "", title: "Edit Text",
                                       prompt: "The words in the text box. A new line starts a new paragraph.",
                                       onOK: { [weak self] t in self?.controller.setTextBoxText(at: i, inline: inline, t); close() },
                                       onCancel: close)
                : kind == .altText
                ? AltTextDialog(initial: image?.altText ?? "", title: image?.altTitle ?? "",
                                onApply: { [weak self] t, head in self?.controller.setImageAltText(at: i, inline: inline, t, title: head); close() },
                                onCancel: close)
                : CropDialog(initial: image?.crop,
                             onOK: { [weak self] c in _ = self?.controller.setImageCrop(at: i, inline: inline, c); close() },
                             onCancel: close)
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: dialog)])
        }
        if _paragraphOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ParagraphDialog(
                    initial: controller.currentParagraphStyle,
                    onOK: { [weak self] f in
                        guard let self else { return }
                        self.controller.setParagraphFormat(f)
                        self.setState { self._paragraphOpen = false }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._paragraphOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _newStyleOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: NewStyleDialog(
                    taken: { [weak self] n in
                        self?.controller.document.styles.styles.contains { $0.name.lowercased() == n.lowercased() } ?? true
                    },
                    onOK: { [weak self] n in
                        guard let self else { return }
                        self.controller.createStyleFromSelection(name: n)
                        self.setState { self._newStyleOpen = false }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._newStyleOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _propertiesOpen {
            var values: [String: String] = [:]
            for f in PropertiesDialog.fields { values[f.key] = controller.document.property(f.key) }
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: PropertiesDialog(
                    values: values,
                    onOK: { [weak self] new in
                        guard let self else { return }
                        self.controller.setProperties(new)
                        self.setState { self._propertiesOpen = false }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._propertiesOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _bookmarkOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: BookmarkDialog(controller: controller, onClose: { [weak self] in
                    guard let self else { return }
                    self.setState { self._bookmarkOpen = false; self.session.summary = self.session.summarize() }
                    self._editorFocus.requestFocus()
                })),
            ])
        }
        if let kind = _pageDesign {
            let close: () -> Void = { [weak self] in
                guard let self else { return }
                self.setState { self._pageDesign = nil; self.session.summary = self.session.summarize() }
                self._editorFocus.requestFocus()
            }
            let dialog: Widget
            switch kind {
            case .watermark:
                dialog = WatermarkDialog(current: WordWatermark.current(in: controller.document), pickPicture: officeScene.pictureRequested,
                                         onOK: { [weak self] c in close(); self?._applyWatermark(c) }, onCancel: close)
            case .pageBorders:
                dialog = PageBordersDialog(initial: controller.sectionPageBorders(), onOK: { [weak self] b, scope in
                    self?.controller.setPageBorders(b, scope: scope); close() }, onCancel: close)
            case .lineNumbers:
                dialog = LineNumbersDialog(initial: session.sectionSetup().lineNumbers, onOK: { [weak self] n in
                    guard let self else { return }
                    var p = self.session.sectionSetup(); p.lineNumbers = n
                    self.session.applyPageSetup(p); close() }, onCancel: close)
            }
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: dialog)])
        }
        if _captionOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: CaptionDialog(controller: controller, onDone: { [weak self] in
                    guard let self else { return }
                    self.setState { self._captionOpen = false; self.session.summary = self.session.summarize() }
                    self._editorFocus.requestFocus()
                })),
            ])
        }
        if _crossReferenceOpen {
            let info = PdfExport.pageInfo(controller.document, pageSetup: session.pageSetup, theme: session.theme)
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: CrossReferenceDialog(
                    controller: controller, pageOf: info.label, pageCount: info.count, onDone: { [weak self] _ in
                        guard let self else { return }
                        self.setState { self._crossReferenceOpen = false; self.session.summary = self.session.summarize() }
                        self._editorFocus.requestFocus()
                    })),
            ])
        }
        if _fieldOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: FieldDialog(
                    clock: FieldClock.current() ?? FieldClock(year: 2000, month: 1, day: 1, hour: 0, minute: 0, second: 0),
                    onOK: { [weak self] instruction in
                        guard let self else { return }
                        self.setState { self._fieldOpen = false }
                        self._insertField(instruction)
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._fieldOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _dateTimeOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: DateTimeDialog(
                    clock: FieldClock.current() ?? FieldClock(year: 2000, month: 1, day: 1, hour: 0, minute: 0, second: 0),
                    onOK: { [weak self] picture, automatic in
                        guard let self else { return }
                        self.controller.insertDateTime(picture: picture, automatic: automatic, clock: FieldClock.current())
                        self.setState { self._dateTimeOpen = false }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._dateTimeOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _commentOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: PictureAltTextDialog(
                    initial: "", title: "New Comment", prompt: "Type the comment. It goes on the selected text, or on the word at the cursor.",
                    onOK: { [weak self] text in
                        guard let self else { return }
                        let id = self.controller.addComment(text)
                        self.setState { self._commentOpen = false }
                        if id == nil { self.session.onStatus?("Select some text to comment on") }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._commentOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _multilevelOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: MultilevelListDialog(
                    initial: controller.multilevelScheme, startLevel: controller.currentListLevel ?? 0,
                    onOK: { [weak self] levels in
                        guard let self else { return }
                        self.controller.setMultilevelFormat(levels)
                        self.setState { self._multilevelOpen = false }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._multilevelOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if _numberingValueOpen {
            return Stack(children: [
                window,
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: NumberingValueDialog(
                    initial: controller.currentNumberValue,
                    onOK: { [weak self] n in
                        guard let self else { return }
                        self.controller.setNumberingValue(n)
                        self.setState { self._numberingValueOpen = false }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._numberingValueOpen = false }
                        self?._editorFocus.requestFocus()
                    })),
            ])
        }
        if let bullet = _listFormatOpen {
            var layers: [Widget] = [window]
            layers.append(
                Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ListFormatDialog(
                    bullet: bullet,
                    initial: controller.currentListFormat ?? (bullet ? ListLevelFormat.bulletLibrary[0] : ListLevelFormat.numberingLibrary[0]),
                    pickSymbol: { [weak self] done in self?.setState { self?._listSymbolPick = done } },
                    onOK: { [weak self] f in
                        guard let self else { return }
                        self.controller.setListFormat(f)
                        self.setState { self._listFormatOpen = nil }
                        self._editorFocus.requestFocus()
                    },
                    onCancel: { [weak self] in
                        self?.setState { self?._listFormatOpen = nil }
                        self?._editorFocus.requestFocus()
                    })))
            if let pick = _listSymbolPick {
                layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SymbolPicker(
                    hooks: SymbolHooks(
                        fonts: ["(current font)"] + OfficeFonts.families(including: controller.currentCharStyle.fontFamily ?? OfficeFonts.defaultFamily),
                        insert: { [weak self] text, font in
                            pick(text, font)
                            self?.setState { self?._listSymbolPick = nil }
                        }),
                    onClose: { [weak self] in self?.setState { self?._listSymbolPick = nil } })))
            }
            return Stack(children: layers)
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
                onPicturePath: { [weak self] path in self?._insertPicture(path) },
                onOpenSite: (widget as? OfficeShell)?.onOpenSite, scene: officeScene)),
        ])
    }

    private func _followLink(_ link: String) {
        if !WriterLinks.follow(link, in: controller, openURL: { hostOpenURL?($0) }) {
            _flash("The link’s destination is no longer in this document.")
        }
    }

    private func _pageArea(_ fluent: FluentThemeData) -> Widget {
        let backdrop = OfficeAppearance.canvas(fluent)
        // Paper stays paper in dark mode, as Google Docs keeps it: only the
        // chrome around it darkens. A dark page made styles with colours of
        // their own (the Title's navy) vanish into it.
        let page = Color(0xFFFFFFFF)
        let theme = session.theme
        theme.textColor = Color(0xFF1B1B1B)
        theme.caretColor = theme.textColor
        theme.selectionColor = fluent.accentColor.defaultBrushFor(.light).withOpacity(0.25)
        let paged = session.viewMode == .printLayout
        let readMargin = session.viewMode == .readMode ? 120.0 : 24.0
        let editable = RichEditable(
            controller: _boxEdit?.main ?? controller, theme: theme,
            padding: EdgeInsets(left: readMargin, top: 24, right: readMargin, bottom: 24),
            focusNode: _editorFocus,
            backgroundColor: paged ? backdrop : page,
            hiddenFrameID: _boxEdit.flatMap { b in b.child != nil ? nil : b.index < b.main.document.paragraphs.count ? b.main.document.paragraphs[b.index].image?.id : nil },
            zoom: session.zoom,
            pageSetup: paged ? session.pageSetup : nil, pageColor: page,
            onPageInfo: { [weak self] p, n in
                guard let self, self.session.pageInfo != (p, n) else { return }
                self.setState { self.session.pageInfo = (p, n) }
            },
            onShortcut: { [weak self] key, mods in self?._shortcut(key, mods) ?? false },
            onCellEdge: _tableTool == "erase" ? { [weak self] t, r, c, side in self?.controller.eraseCellEdge(table: t, row: r, column: c, side: side) } : nil,
            onCellEdgeStroke: _tableTool == "erase" ? { [weak self] begin in if begin { self?.controller.breakUndoCoalescing() } } : nil,
            onDrawTable: _tableTool == "draw" ? { [weak self] cell, dx, dy in self?.controller.drawTable(in: cell, dx: dx, dy: dy) } : nil,
            onLinkHover: { [weak self] link in
                guard let self, self._linkHover != link else { return }
                self.setState {
                    self._linkHover = link
                    if let link, link != self._hoverCard { self._hoverCard = link; self._cardDismissed = false }
                }
            },
            onLinkActivate: { [weak self] link in self?._followLink(link) },
            onNoteActivate: { [weak self] n, box in self?._openNote(n, box: box) },
            onCommentActivate: { [weak self] id, box in self?._openCommentCard(id, box: box) },
            // Format Painter applies when a selection gesture ends, as Word does.
            onSelectionGestureEnd: { [weak self] in self?._applyPainter() },
            onHeaderFooterEdit: { [weak self] _ in self?.session.onHeaderFooter?() },
            onContextMenu: { [weak self] point in self?._showContextMenu(at: point) },
            onTouchMenu: { [weak self] rect in self?._showTouchMenu(rect) },
            onPasteOptions: { [weak self] point in self?._showPasteOptions(at: point) },
            spellChecker: session.checkSpelling ? _spelling : nil,
            onTextBoxEnter: { [weak self] index, inline, rect in self?._enterBox(index, inline, rect) },
            onBoxRect: _boxEdit == nil ? nil : { [weak self] r in
                guard let self, let r, let b = self._boxEdit, b.rect != r else { return }
                self.setState { self._boxEdit?.rect = r }
            },
            onNestedTableEnter: { [weak self] index, rect, at, frame in self?._enterBox(index, nil, rect, at: at, frame: frame) }
        )
        guard let b = _boxEdit else {
            return WriterAccessibility.wrap(editable, controller: controller, focused: _editorFocus.hasFocus)
        }
        let z = session.zoom
        // The shape's own frame (its line and fill) is drawn round the editor, so the frame grows with the words
        // instead of staying the size the page was laid out at.
        let frame = (b.child != nil ? nil : b.index < b.main.document.paragraphs.count ? b.main.document.paragraphs[b.index].image?.outline : nil).flatMap { $0.kind == .box ? $0 : nil }
        // A table nested in a cell has no inset: its cells stay where the page draws them.
        let nested = b.child == nil && b.inline == nil && b.main.isNestedTable(at: b.index)
        let inset = nested ? 0 : 1.0
        let boxEditor = RichEditable(
            controller: controller, theme: theme,
            padding: EdgeInsets(left: 7.2 * z * inset, top: 3.6 * z * inset, right: 7.2 * z * inset, bottom: 3.6 * z * inset),
            focusNode: _boxFocus, backgroundColor: frame?.fill ?? Color(0xFFFFFFFF), zoom: z,
            onShortcut: { [weak self] key, mods in self?._shortcut(key, mods) ?? false },
            scrolls: false,
            onContentHeight: { [weak self] h in
                guard let self, self._boxEdit != nil, self._boxContentHeight != h else { return }
                self.setState { self._boxContentHeight = h }
            },
            caretAt: _boxCaretAt,
            boxRules: _boxRules)
        // A box that fits its text grows as the words do.
        var boxHeight = b.rect.height
        if let h = _boxContentHeight, b.autoFit { boxHeight = h + 7.2 * z * inset }
        return Stack(children: [
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: editable),
            // A press anywhere outside the box ends the edit (and still reaches the page under it).
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Listener(
                onPointerDown: { [weak self] _ in self?._leaveBox() }, behavior: .translucent, child: SizedBox(expand: ()))),
            Positioned(left: b.rect.left, top: b.rect.top, width: max(b.rect.width, _boxRules?.width ?? 0), height: boxHeight, child: framed(boxEditor, frame, z)),
        ])
    }

    private func framed(_ editor: Widget, _ frame: ShapeOutline?, _ zoom: Double) -> Widget {
        guard let f = frame, let line = f.color, f.width > 0 else { return editor }
        return Stack(children: [
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: editor),
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: IgnorePointer(child: DecoratedBox(
                decoration: BoxDecoration(border: Border.all(color: line, width: max(1, f.width * zoom)))))),
        ])
    }

    /// Start typing in the text box at `index`: the ribbon and the keys act on a controller over the box's own paragraphs
    /// until `_leaveBox` puts them back, as one undo step.
    /// `at`: the click that opened it (this view's coordinates), where the caret goes.
    /// `frame`: the page's layout of a nested table's text (`RichLayout.boxFrame`), which the editor keeps to.
    func _enterBox(_ index: Int, _ inline: String?, _ rect: Rect, at: Offset? = nil, frame: (layout: RichLayout, document: RichDocument)? = nil) {
        let child = inline == nil ? controller.groupChild : nil
        guard _boxEdit == nil, var inside = (child != nil ? controller.groupChildTextDocument() : controller.textBoxDocument(at: index, inline: inline)) else { return }
        // (A nested table keeps the page's layout while edited: its document's settings and the layout's width and rules.)
        let rules = child == nil && inline == nil && controller.isNestedTable(at: index) && frame?.document.paragraphs == inside.paragraphs ? frame : nil
        if let rules {
            var same = rules.document
            same.tableStyles = inside.tableStyles
            same.tableColumns = inside.tableColumns
            inside = same
        }
        let main = controller
        if inside.paragraphs.isEmpty { inside.paragraphs = [RichParagraph(text: "")] }
        let box = RichDocumentController(document: inside)
        box.clipboardCodec = OfficeClipboardCodec()
        box.addListener { [weak self] in
            guard let self, self._boxEdit != nil else { return }
            let s = self.session.summarize()
            if s != self.session.summary { self.setState { self.session.summary = s } }
        }
        setState {
            _boxEdit = (index, inline, rect, main, child == nil && main.textBoxAutoHeight(at: index, inline: inline), child)
            _boxContentHeight = nil
            _boxCaretAt = at.map { Offset($0.dx - rect.left, $0.dy - rect.top) }
            _boxRules = rules?.layout
            session.controller = box
            session.nestedTableHost = child == nil && inline == nil && main.isNestedTable(at: index) ? (main, index) : nil
            session.summary = session.summarize()
        }
        ScreenReader.announce("Editing text box. Escape to finish.", priority: .assertive)
        _boxFocus.requestFocus()
    }

    /// Put the box's words back into the document (one undo step) and return to the page.
    func _leaveBox() {
        guard let b = _boxEdit else { return }
        let box = controller
        setState {
            _boxEdit = nil
            _boxRules = nil
            session.controller = b.main
            session.nestedTableHost = nil
        }
        if let (xml, boxRels, media) = TextBoxInsert.contentAndMedia(box.document) {
            let rels = b.main.keepBoxMedia(media, rels: boxRels)
            if b.child != nil {
                b.main.setGroupChildText(document: box.document, contentXML: xml, rels: rels)
            } else {
            let fitted = b.autoFit ? _boxContentHeight.map { ($0 + 7.2 * session.zoom) / session.zoom } : nil
            b.main.setTextBoxContent(at: b.index, inline: b.inline, document: box.document, contentXML: xml, rels: rels, height: fitted)
            }
        }
        if b.child == nil, b.inline == nil, b.main.isNestedTable(at: b.index), b.index + 1 < b.main.document.paragraphs.count,
           b.main.document.paragraphs[b.index + 1].cell != nil {
            // W-TB-5: leaving a nested table puts the caret in the outer cell under it, not on the table as an object.
            b.main.moveTo(RichPosition(paragraph: b.index + 1, offset: 0), extend: false)
        }
        setState { session.summary = session.summarize() }
        ScreenReader.announce("Text box saved")
        _editorFocus.requestFocus()
    }
}

/// `text` between two UTF-16 offsets (the spell checker's ranges), as a
/// String — `NSString.substring(with:)` without the legacy Foundation
/// layer, which the browser build does not link.
/// The recent-files list, shared by Writer and Slides: one file beside the
/// user's other Starling state.
/// Where an untitled document's recovery copy lives. `OFFICE_RECOVERY_DIR`
/// moves it: the test drivers point it at a scratch directory, so a driven
/// instance never opens — or overwrites — the copy of the user's own
/// untitled document (one did, 2026-09-30).
enum OfficeRecovery {
    static func untitled(_ ext: String) -> String {
        let dir = ProcessInfo.processInfo.environment["OFFICE_RECOVERY_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            ?? homeDirectory() + "/.config/starling/office-recovery"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/untitled.\(ext)~"
    }
}

/// The user's settings, kept across launches in one small file beside the
/// recent-files list (`key=value` lines). A driven instance keeps its own,
/// as it does its recent files.
enum OfficeSettings {
    private static var _file: String {
        let dir = ProcessInfo.processInfo.environment["OFFICE_RECOVERY_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            ?? homeDirectory() + "/.config/starling"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/office-settings.txt"
    }
    nonisolated(unsafe) private static var _values: [String: String]? = nil
    private static var values: [String: String] {
        if let v = _values { return v }
        var v: [String: String] = [:]
        #if !os(WASI)
        if let text = try? String(contentsOfFile: _file, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map { String($0).trimmingWhitespace() }
                if parts.count == 2 { v[parts[0]] = parts[1] }
            }
        }
        #endif
        _values = v
        return v
    }
    private static func set(_ key: String, _ value: String) {
        var v = values
        v[key] = value
        _values = v
        #if !os(WASI)
        try? v.keys.sorted().map { "\($0)=\(v[$0]!)" }.joined(separator: "\n").write(toFile: _file, atomically: true, encoding: .utf8)
        #endif
    }

    /// Any other setting by name (the update check keeps its state here).
    static func string(_ key: String) -> String? { values[key] }
    static func setString(_ key: String, _ value: String) { set(key, value) }

    /// Draw a document's fonts with the faces this computer has, where it
    /// has them (the default), or always with Starling's matching fonts.
    static var useInstalledFonts: Bool {
        get { values["fonts"] != "bundled" }
        set {
            set("fonts", newValue ? "installed" : "bundled")
            OfficeFonts.fontSourceChanged()
        }
    }
}

enum OfficeRecent {
    private static var _file: String {
        // (A driven instance keeps its list with its recovery copies:
        // the test drivers' scratch files filled the user's own Recent
        // list — fourteen of its twenty places, 2026-10-13.)
        let dir = ProcessInfo.processInfo.environment["OFFICE_RECOVERY_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            ?? homeDirectory() + "/.config/starling"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/office-recent.txt"
    }

    static func load() -> [String] {
        #if os(WASI)
        // No files, so no recent files. (FileManager.createDirectory with
        // intermediates recurses forever on WASI, so this cannot even try.)
        return []
        #else
        guard let text = try? String(contentsOfFile: _file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init).filter { FileManager.default.fileExists(atPath: $0) }
        #endif
    }

    static func remember(_ path: String, in list: [String]) -> [String] {
        #if os(WASI)
        // A tab cannot reopen a file by name: nothing to remember.
        return list
        #endif
        var recent = list
        recent.removeAll { $0 == path }
        recent.insert(path, at: 0)
        if recent.count > 20 { recent.removeLast(recent.count - 20) }
        #if !os(WASI)
        try? recent.joined(separator: "\n").write(toFile: _file, atomically: true, encoding: .utf8)
        #endif
        return recent
    }
}

func _utf16Slice(_ text: String, _ r: Range<Int>) -> String {
    let u = text.utf16
    guard r.lowerBound >= 0, r.upperBound <= u.count else { return "" }
    let a = u.index(u.startIndex, offsetBy: r.lowerBound)
    let b = u.index(u.startIndex, offsetBy: r.upperBound)
    return String(u[a ..< b]) ?? ""
}

/// The update check's state, in the settings file.
final class SettingsUpdateStore: UpdateStore {
    func get(_ key: String) -> String? { OfficeSettings.string(key) }
    func set(_ key: String, _ value: String) { OfficeSettings.setString(key, value) }
}

/// Gives a control of the comment card a stable id, for tests and the Mac driver.
private final class CardKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}
