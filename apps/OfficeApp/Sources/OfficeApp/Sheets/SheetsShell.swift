// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Sheets window: the title row and ribbon (shared with Writer and
// Slides), the formula bar with its name box, the grid, the sheet tabs,
// and a status bar that sums the selection. Backstage is the shared one,
// with the workbook's own New, Open and Save.

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation
#if os(WASI)
import FlutterWeb
#endif

final class SheetsShell: StatefulWidget {
    let initialPath: String?
    let onSwitch: (DocumentKind, String?) -> Void

    init(initialPath: String?, onSwitch: @escaping (DocumentKind, String?) -> Void) {
        self.initialPath = initialPath
        self.onSwitch = onSwitch
        super.init()
    }

    override func createState() -> State<StatefulWidget> { SheetsShellState() }
}

final class SheetsShellState: State<StatefulWidget> {
    private let _leakProbe = LeakProbe("SheetsShellState")
    let session = OfficeSession(kind: .workbook)
    var wb: WorkbookController { session.workbook! }
    private let _gridKey = GlobalKey<State<StatefulWidget>>()
    var _grid: SheetGridState? { _gridKey.currentState as? SheetGridState }
    private let _formula = TextEditingController()
    private let _nameBox = TextEditingController()
    private let _search = TextEditingController()
    /// The formula bar is being typed in (its text is the user's, not the cell's).
    private var _formulaEditing = false
    /// A cell is being typed in (its text is the grid's, not the formula bar's).
    private var _cellEditing = false
    /// The shell is writing the formula bar's text itself. This port's
    /// FluentTextBox reports a programmatic change through onChanged too
    /// (Flutter's does not), and without this the mirror of the cell
    /// editor read as the user typing in the bar.
    private var _settingFormula = false

    private func _setFormulaText(_ s: String) {
        guard _formula.text != s else { return }
        _settingFormula = true
        _formula.text = s
        _settingFormula = false
    }
    private var _tab = RibbonTab.home
    private var _ribbonCollapsed = false
    private var _backstage: BackstagePage? = nil
    private var _status: String? = nil
    private var _statusGeneration = 0
    private var _recent: [String] = []
    /// In a browser tab: the page's handle on the file the workbook came from or was saved to, so Save writes
    /// back into it (web-parity 4); nil when Save must ask for a place or download.
    private var _browserHandle: Int?
    /// The active sheet's zoom (saved with it), as a factor.
    private var _zoom: Double {
        get { Double(wb.sheet.zoomPercent) / 100 }
        set { wb.setZoom(percent: Int((newValue * 100).rounded())) }
    }
    private var _windowTitle = ""
    /// The sheet tab being renamed, and its text.
    private var _renaming: Int? = nil
    private let _renameText = TextEditingController()
    private var _lastTabClick: (index: Int, at: Date)? = nil
    private var _findOpen = false
    private var _namesOpen = false
    private var _createNamesOpen = false
    private var _protectOpen: Bool? = nil   // nil closed; false = sheet, true = workbook structure
    /// The Format Cells dialog is open (X-FM-1).
    private var _formatOpen = false
    private var _formatTab = 0
    /// Home → Fill Color (true) or Font Color (false) → More Colors… is open.
    private var _moreColorsFill: Bool?
    private var _lineColorOpen = false
    private var _cellsDialog: Bool? = nil          // Insert (true) or Delete (false) cells
    private var _sizeDialog: SizeKind? = nil
    private var _pageSetupOpen = false
    private var _printOpen = false
    private var _shortcutsOpen = false
    var _printKinds: [PrintWhat] = []
    var _printCounts: [Int] = []
    private var _alertOpen: (alert: ValidationAlert, answer: (ValidationChoice) -> Void)?
    private var _sortOpen: (range: CellRange, hasHeader: Bool)?
    private var _consOpen = false
    private var _seriesOpen = false
    private var _scnOpen = false
    private var _goalOpen = false
    private var _chartTitlesOpen: Int? = nil
    private var _dtOpen = false
    private var _chartSeriesOpen: Int? = nil
    private var _chartColorsOpen: Int? = nil
    private var _chartLabelsOpen: Int? = nil
    private var _chartAxisOpen: Int? = nil
    private var _sparklineOpen = false
    private var _chartForm: ChartFormKind? = nil
    private var _sparklineKind: SparklineGroup.Kind? = nil
    private var _dupOpen: (range: CellRange, hasHeader: Bool)?
    private var _ttcOpen: CellRange?
    private var _subOpen: CellRange?
    private var _pvValueOpen: Int?
    private var _pvGroupOpen: Int?
    private var _validationOpen = false
    private var _cfOpen = false
    private var _cfRulesOpen = false
    private var _tableOpen = false
    private var _pivotOpen = false
    private var _filterOpen: (col: Int, kind: String)?
    private let _tabProbes = SheetTabProbes()
    private var _tabDrag: (from: Int, x: Double, moved: Bool)? = nil
    /// Sheet whose Tab Color or Move or Copy dialog is open.
    private var _tabColorFor: Int? = nil
    private var _moveCopyFor: Int? = nil
    private var _pasteOpen = false
    private var _symbolOpen = false
    /// The Insert Hyperlink dialog is open (X-LK-1).
    private var _linkOpen = false
    private var _altOpen = false
    private let _findQuery = TextEditingController()
    private let _contextMenu = FlyoutController()
    private let _filterMenu = FlyoutController()

    private var _w: SheetsShell { widget as! SheetsShell }

    // MARK: Lifecycle

    override func initState() {
        super.initState()
        trackDocumentPath(session)
        // Whatever AutoSave has not yet written: a window's host closing (or the app quitting) must not drop what is unsaved. On iPad
        // the workbook is written to its own file; on the Mac, to a recovery copy beside it (as Writer does) that the
        // next open offers, and the file itself is left as the user last saved it.
        officeScene.setPictureDrop({ [weak self] path in self?._insertPicture(path) }, owner: self)
        officeScene.registerFlush(owner: self) { [weak self] in
            // In a browser tab (hidden or closing): the page's copy, now rather than after the pause.
            if let self, OfficeHost.browserRecovery != nil { self._keepInBrowser(); return }
            guard let self, self.session.dirty, let path = self.session.path,
                  ["xlsx", "csv", "tsv"].contains(path.pathExtension.lowercased()) else { return }
            #if os(macOS)
            self._writeRecovery(for: path)
            #else
            self._saveTo(path)
            #endif
        }
        OfficeFonts.register()
        _recent = OfficeHost.browserRecent?.names() ?? OfficeRecent.load()
        _wire()
        wb.addListener({ [weak self] in self?._changed() }, owner: self)
        _publishToolbar()
        wb.onCommand = { [weak self] cmd in self?._command(cmd) }
        wb.onValidationAlert = { [weak self] alert, answer in
            self?.setState { self?._alertOpen = (alert, answer) }
        }
        session.onFind = { [weak self] replace in self?._openFind(replace: replace) }
        session.onToggleAutoSave = { [weak self] in
            guard let self else { return }
            self.setState { self.session.autoSave.toggle() }
            self._flash(self.session.autoSave ? "AutoSave on" : "AutoSave off")
            self._scheduleAutosave()
        }
        // `starling.debug('sheet')` from the browser's console or a script:
        // the active sheet as laid out, to diff against
        // `OfficeApp --sheet-layout` natively (test/sheets-layout.sh).
        hostDebugQuery = { [weak self] kind in
            // `starling.debug('pdf')`: File → Export → PDF without the clicks —
            // the download is what a script then compares. 'name' and
            // 'status' are how that script knows where it is: the open
            // document's name, and the status bar's message.
            #if os(WASI)
            if kind == "pdf" { self?._export("pdf"); return "exporting" }
            if kind == "controls", let self { return ControlList.text(self.context) }
            // 'book-pdf': the entire workbook, cut off where the rendering
            // gate cuts Excel's (test/xlsx-app-render.sh) — what
            // `--sheet-pdf` writes natively.
            if kind == "book-pdf", let self, let grid = self._grid {
                let name = self.session.title.deletingPathExtension + ".pdf"
                Task { @MainActor [weak self] in
                    let ok = await grid.writePdf(to: name, title: self?.session.title ?? "", filePath: self?.session.path,
                                                 wholeBook: true, maxPages: 20)
                    self?._flash(ok ? "Exported \(name)" : "Nothing to export in this workbook")
                }
                return "exporting"
            }
            if kind == "name" { return self?.session.title }
            if kind == "status" { return self?._status ?? "" }
            #endif
            guard let self, kind == "sheet" else { return nil }
            _ = self._grid?.commitEdit()
            return SheetLayoutDump.text(self.wb)
        }
        if let path = _w.initialPath {
            // Bytes from the browser's picker that crossed the kind switch
            // (an .xlsx picked in Writer or Slides) arrive by name, not on disk.
            // A browser tab's recovery copy that Writer found at start and handed on opens unsaved.
            if let data = PickedFile.takeRecovered(path) { _open(path, data: data, recovered: true) }
            else if let data = PickedFile.take(path) { _open(path, data: data, handle: PickedFile.takenHandle) }
            else { _open(path) }
        } else if let row = OfficeHost.browserRecovery?.take("xlsx") {
            // A tab closed with unsaved changes: its copy, under the name it would have saved as.
            _open(row.name, data: row.data, recovered: true)
        }
        _syncBars()
        #if os(macOS)
        ScriptedInput.exportPdf = { [weak self] path in
            guard let self, let grid = self._grid else { return false }
            _ = grid.commitEdit()
            return await grid.writePdf(to: path, title: self.session.title, filePath: self.session.path)
        }
        #endif
    }

    override func dispose() {
        officeScene.publishToolbar(nil, owner: self)
        officeScene.unregisterFlush(owner: self)
        officeScene.setPictureDrop(nil, owner: self)
        officeScene.setDocumentPath(nil, owner: self)
        wb.removeListeners(owner: self)
        _formula.dispose()
        _nameBox.dispose()
        _findQuery.dispose()
        _search.dispose()
        _renameText.dispose()
        super.dispose()
    }

    private func _wire() {
        session.onBackstage = { [weak self] open in self?.setState { self?._backstage = open ? .home : nil } }
        session.onNew = { [weak self] in self?._newWorkbook() }
        session.guardWindowClose()
        session.routeFieldChords()
        session.onNewKind = { [weak self] kind in
            guard let self else { return }
            if kind == .workbook { self._newWorkbook() } else { self._w.onSwitch(kind, nil) }
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
                _ = self._grid?.commitEdit()
                self.wb.stashViewState()
                let name = self.session.path.map { $0.lastPathComponent }
                    ?? self.session.title.deletingPathExtension + ".xlsx"
                ask(name, { [weak self] path, finished in
                    guard let self else { finished(false); return }
                    let ext = path.pathExtension.lowercased()
                    let data: Data?
                    if ext == "csv" || ext == "tsv" {
                        data = Data(Csv.write(self.wb.sheet, book: self.wb.book, separator: ext == "tsv" ? "\t" : ",").utf8)
                    } else {
                        data = try? Xlsx.write(self.wb.book)
                    }
                    finished((try? data?.write(to: URL(fileURLWithPath: path))) != nil)
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
        session.onPrint = { [weak self] in self?._print() }
        session.onShortcuts = { [weak self] in self?.setState { self?._backstage = nil; self?._shortcutsOpen = true } }
        session.onStatus = { [weak self] m in self?._flash(m) }
        session.onUndo = { [weak self] in self?.wb.undo() }
        session.onRedo = { [weak self] in self?.wb.redo() }
    }

    private func _changed() {
        guard mounted else { return }
        if let n = wb.chartNotice { wb.chartNotice = nil; _flash(n) }
        session.dirty = wb.edits != 0
        _scheduleAutosave()
        // The title bar's Undo and Redo read the session's summary, which
        // only the Writer fills in; without this they stayed greyed out.
        session.summary.canUndo = wb.canUndo
        session.summary.canRedo = wb.canRedo
        _syncBars()
        _publishToolbar()
        setState {}
    }

    /// AutoSave: with it on (the default on iPad, where nothing else saves a workbook) and a file behind the workbook,
    /// the file is rewritten after every pause in editing, quietly: no "Saved" flash, no closing the backstage, and
    /// never while a cell is mid-typing (the pause that follows commits it, and `_changed` runs again).
    private var _autosaveGeneration = 0
    /// The data revision (`wb.edits` goes back to 0 on a save, and down on undo) whose copy the browser page already holds: a page hide asks again, and an unchanged
    /// workbook is not rewritten.
    private var _keptChanges: Int?
    private func _scheduleAutosave() {
        if OfficeHost.browserRecovery != nil {
            // The browser has no files of ours: only the page's recovery copy, kept whatever AutoSave says.
            guard session.dirty else { return }
        } else {
            #if os(WASI)
            return
            #else
            guard session.autoSave, session.dirty else { return }
            #endif
        }
        _autosaveGeneration += 1
        let gen = _autosaveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + OfficeHost.autosaveDelay) { [weak self] in
            guard let self, self.mounted, self._autosaveGeneration == gen else { return }
            self._autosaveNow()
        }
    }

    /// In a browser tab: the unsaved workbook goes to the page's storage as an xlsx row, under the name it would
    /// save as. A cell mid-typing is left alone (as AutoSave leaves it): the pause after it commits comes back here.
    private func _keepInBrowser() {
        guard let browser = OfficeHost.browserRecovery, session.dirty, _keptChanges != wb.dataRevision,
              _grid?.edit == nil else { return }
        wb.stashViewState()
        guard let data = try? Xlsx.write(wb.book) else { return }
        let name = session.path?.lastPathComponent ?? session.title
        browser.keep("xlsx", name.deletingPathExtension + ".xlsx", data)
        _keptChanges = wb.dataRevision
    }

    /// Saved, or a new workbook: no copy to come back to.
    private func _dropBrowserCopy() {
        _keptChanges = nil
        OfficeHost.browserRecovery?.discard()
    }

    private func _autosaveNow() {
        if OfficeHost.browserRecovery != nil {
            if _grid?.edit != nil { _scheduleAutosave(); return }
            _keepInBrowser()
            return
        }
        #if !os(WASI)  // (never scheduled there: the browser has no file to rewrite, and no atomic writes)
        guard session.autoSave, session.dirty, let path = session.path,
              ["xlsx", "csv", "tsv"].contains(path.pathExtension.lowercased()) else { return }
        // A cell being typed in is not ours to commit: try again after the next pause.
        if _grid?.edit != nil { _scheduleAutosave(); return }
        wb.stashViewState()
        do {
            let data: Data
            switch path.pathExtension.lowercased() {
            case "xlsx": data = try Xlsx.write(wb.book)
            case let f: data = Data(Csv.write(wb.sheet, book: wb.book, separator: f == "tsv" ? "\t" : ",").utf8)
            }
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            officeScene.documentSaved?(path)
            wb.markSaved()
            setState { session.dirty = false }
        } catch {
            _flash("AutoSave could not write \(path.lastPathComponent): \(plainFailure(error))")
        }
        #endif
    }

    /// The keyboard's toolbar while a cell is being typed in: undo and redo,
    /// and the active cell's bold, italic and underline (a cell has no lists).
    private func _publishToolbar() {
        guard officeScene.toolbarChanged != nil else { return }
        let wb = self.wb
        let st = wb.style(at: wb.active)
        officeScene.publishToolbar(.init(
            canUndo: wb.canUndo, canRedo: wb.canRedo,
            bold: st.bold, italic: st.italic, underline: st.underline,
            // (Weak: UIKit keeps the buttons past the window, and a strong workbook kept a closed window's data alive.)
            undo: { [weak wb] in wb?.undo() }, redo: { [weak wb] in wb?.redo() },
            toggleBold: { [weak wb] in wb?.toggleStyle(\.bold) }, toggleItalic: { [weak wb] in wb?.toggleStyle(\.italic) },
            toggleUnderline: { [weak wb] in wb?.toggleStyle(\.underline) },
            // While a cell is typed in, the keys a formula needs and a soft keyboard hides on another page; otherwise what
            // typing numbers into cells reaches for: a total, a number format, and a clean cell.
            context: _cellEditing ? Self._formulaKeys { [weak self] in self?._grid } : [
                .init(id: "ctx-cell-sum", title: "AutoSum", symbol: "sum") { [weak wb] in if let wb { Ribbon._autoSum(wb) } },
                .init(id: "ctx-cell-currency", title: "Currency", symbol: "dollarsign") { [weak wb] in wb?.setStyle { $0.numberFormat = "$#,##0.00" } },
                .init(id: "ctx-cell-percent", title: "Percent Style", symbol: "percent") { [weak wb] in wb?.setStyle { $0.numberFormat = "0%" } },
                OfficeHost.colorButton(id: "ctx-cell-fill", title: "Fill Color", symbol: "paintpalette", none: "No Fill") { [weak wb] color in
                    wb?.setStyle { $0.fill = color.map { UInt32(truncatingIfNeeded: $0.value) & 0xFFFFFF } }
                },
                .init(id: "ctx-cell-sort", title: "Sort", symbol: "arrow.up.arrow.down", children: [
                    .init(id: "ctx-sort-az", title: "Sort A to Z", symbol: "") { [weak wb] in wb?.sortSelection(ascending: true) },
                    .init(id: "ctx-sort-za", title: "Sort Z to A", symbol: "") { [weak wb] in wb?.sortSelection(ascending: false) },
                ]) {},
                .init(id: "ctx-cell-clear", title: "Clear Contents", symbol: "eraser") { [weak wb] in wb?.clearContents() },
                .init(id: "ctx-cell-format", title: "Format Cells", symbol: "number") { [weak self] in self?._openFormatCells() },
            ]), owner: self)
    }

    /// The formula keys: each types its text at the caret (the arithmetic, comparison and text operators, brackets, the range
    /// and list separators and the absolute-reference `$`), F4 cycles the reference at the caret absolute and relative.
    private static func _formulaKeys(_ grid: @escaping () -> SheetGridState?) -> [OfficeScene.ToolbarButton] {
        func key(_ shown: String, _ typed: String, _ name: String) -> OfficeScene.ToolbarButton {
            .init(id: "ctx-key-\(name)", title: shown, symbol: "") { grid()?.typeText(typed) }
        }
        return [
            key("=", "=", "equals"), key("+", "+", "plus"), key("−", "-", "minus"), key("*", "*", "times"), key("/", "/", "divide"),
            key("(", "(", "open"), key(")", ")", "close"), key(":", ":", "colon"), key(",", ",", "comma"), key("$", "$", "dollar"),
            .init(id: "ctx-key-f4", title: "F4", symbol: "") { grid()?.cycleAbsoluteReference() },
            // The rest of a formula's operators, which sit two pages deep on the soft keyboard. After F4, so a narrow bar
            // folds these into More first.
            key("^", "^", "power"), key("%", "%", "percent"), key("&", "&", "concat"),
            key("<", "<", "less"), key(">", ">", "greater"), key("\"", "\"", "quote"),
        ]
    }

    /// The name box shows the active cell (or the selection's size while
    /// dragging); the formula bar shows what was typed into it.
    private func _syncBars() {
        // The name box names the active cell whatever is selected, as
        // Excel's does (a whole row selected still reads "A6").
        let name = wb.active.a1
        if _nameBox.text != name { _nameBox.text = name }
        if !_formulaEditing && _grid?.edit == nil { _setFormulaText(wb.input(wb.active)) }
    }

    private func _pickPicture() {
        #if os(WASI)
        WebFiles.open(extensions: ["png", "jpg", "jpeg", "gif", "bmp"]) { [weak self] picked in
            guard let self, let picked else { return }
            self._placePicture(picked.name, data: picked.data)
        }
        #else
        if let ask = officeScene.pictureRequested {
            ask { [weak self] path in if let path { self?._insertPicture(path) } }
            return
        }
        setState { _backstage = .insertPicture }
        #endif
    }

    private func _insertPicture(_ path: String) {
        setState { _backstage = nil }
        guard let data = FileManager.default.contents(atPath: path) else {
            _flash("Could not read \(path.lastPathComponent)")
            return
        }
        _placePicture(path.lastPathComponent, data: data)
    }

    private func _placePicture(_ name: String, data: Data) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let codec = try await instantiateImageCodec([UInt8](data))
                let frame = try await codec.getNextFrame()
                codec.dispose()
                // Pixels read as 96 per inch, so 0.75 point each.
                let w = Double(frame.image.width) * 0.75, h = Double(frame.image.height) * 0.75
                frame.image.dispose()
                self.wb.insertPicture(name: name, data: data, width: w, height: h)
                self._grid?.focus.requestFocus()
            } catch {
                self._flash("Could not open \(name) as a picture")
            }
        }
    }

    private func _flash(_ message: String) {
        _statusGeneration += 1
        let gen = _statusGeneration
        setState { _status = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.mounted, self._statusGeneration == gen else { return }
            self.setState { self._status = nil }
        }
    }

    private func _command(_ cmd: SheetCommand) {
        guard let grid = _grid else { return }
        switch cmd {
        case .cellsDialog(let insert): _openCellsDialog(insert: insert)
        case .sizeDialog(let k): _openSizeDialog(k)
        case .copy: grid.copySelection()
        case .cut: grid.copySelection(cut: true)
        case .paste: grid.paste()
        case .pasteSpecial: _openPasteSpecial()
        case .formatPainter:
            if wb.painterSource == nil { wb.armFormatPainter() } else { wb.cancelFormatPainter() }
        case .symbol: setState { _symbolOpen = true }
        case .startFormula(let text):
            grid.focus.requestFocus()
            grid.beginEdit(replace: text)
        case .zoom(let factor):
            setState { _zoom = factor == 0 ? 1 : max(0.25, min(4, _zoom * factor)) }
        case .toggleSplit:
            grid.toggleSplit()
        case .toggleGridlines:
            wb.toggleGridlines()
        case .status(let m):
            _flash(m)
        case .editNote:
            _editNote(at: wb.active)
        case .conditionalFormat:
            setState { _cfOpen = true }
        case .conditionalRules:
            setState { _cfRulesOpen = true }
        case .dataValidation:
            setState { _validationOpen = true }
        case .consolidate:
            setState { _consOpen = true }
        case .fillSeries:
            setState { _seriesOpen = true }
        case .scenarioManager:
            setState { _scnOpen = true }
        case .chartTitles(let i):
            setState { _chartTitlesOpen = i }
        case .dataTable:
            if wb.selection.bottom > wb.selection.top, wb.selection.right > wb.selection.left { setState { _dtOpen = true } }
            else { _flash(DataTableProblem.selectionTooSmall.message) }
        case .chartSeries(let i):
            setState { _chartSeriesOpen = i }
        case .chartColors(let i):
            setState { _chartColorsOpen = i }
        case .chartAxis(let i):
            setState { _chartAxisOpen = i }
        case .chartLabels(let i):
            setState { _chartLabelsOpen = i }
        case .chartForm(let kind):
            setState { _chartForm = kind }
        case .sparklineDialog(let kind):
            setState { _sparklineOpen = true; _sparklineKind = kind }
        case .goalSeek:
            setState { _goalOpen = true }
        case .removeDuplicates:
            if let region = wb.sortRegion() { setState { _dupOpen = region } }
            else { _flash(DuplicatesProblem.nothingToCheck.message) }
        case .textToColumns:
            let r = wb.selection
            if r.left == r.right, r.bottom > r.top { setState { _ttcOpen = r } }
            else { _flash(TextToColumnsProblem.oneColumn.message) }
        case .subtotal:
            if let region = wb.sortRegion() { setState { _subOpen = region.range } }
            else { _flash(SubtotalProblem.nothingToTotal.message) }
        case .sortDialog:
            if let region = wb.sortRegion() { setState { _sortOpen = region } }
            else { _flash(SortProblem.nothingToSort.message) }
        case .insertPicture: _pickPicture()
        case .altText:
            if let i = wb.selectedDrawing, wb.sheet.drawings.indices.contains(i), wb.sheet.drawings[i].kind != .other {
                setState { _altOpen = true }
            }
        case .insertPivotTable:
            setState { _pivotOpen = true }
        case .tableDialog:
            setState { _tableOpen = true }
        case .columnFilter(let col, let kind):
            setState { _filterOpen = (col, kind) }
        case .nameManager:
            setState { _namesOpen = true }
        case .formatCells(let tab):
            _openFormatCells(tab: tab)
        case .moreColors(let fill):
            setState { _moreColorsFill = fill }
        case .moreLineColor:
            setState { _lineColorOpen = true }
        case .useName(let name):
            grid.focus.requestFocus()
            if grid.isEditing { grid.typeText(name) } else { grid.beginEdit(replace: "=" + name) }
        case .createNames:
            setState { _createNamesOpen = true }
        case .protectSheetDialog:
            setState { _protectOpen = false }
        case .protectWorkbookDialog:
            setState { _protectOpen = true }
        case .pageSetup:
            setState { _pageSetupOpen = true }
        }
    }

    // MARK: Files

    private func _newWorkbook() {
        _dropBrowserCopy()
        _browserHandle = nil
        wb.load(Workbook())
        session.path = nil
        session.dirty = false
        setState { _backstage = nil }
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
        if kind != .workbook {
            _w.onSwitch(kind, path)
            return
        }
        #if os(WASI)
        // A tab has no files by path; the picker (⌘O) hands bytes over.
        _flash("Open a workbook with ⌘O".keys)
        #else
        guard let data = FileManager.default.contents(atPath: path) else {
            _flash("Could not open \(path.lastPathComponent)")
            return
        }
        #if os(macOS)
        // A recovery copy newer than the file: the last session ended with unsaved edits. Load it, unsaved.
        if let r = _recoveryIfNewer(than: path) {
            if let copy = FileManager.default.contents(atPath: r), (try? Workbook.open(copy, name: path.lastPathComponent)) != nil {
                _load(copy, from: path)
                wb.markUnsaved()
                _flash("Restored unsaved changes to \(path.lastPathComponent) — Save to keep them")
                return
            }
            // A copy that does not read (a crash mid-write) never blocks the file.
            try? FileManager.default.removeItem(atPath: r)
        }
        #endif
        _load(data, from: path)
        #endif
    }

    #if os(macOS)
    /// Where a workbook's recovery copy lives: beside it as `name.xlsx~` (Writer's `name.docx~`). Always xlsx bytes,
    /// whatever the file's own format.
    private func _recoveryPath(for path: String) -> String { path + "~" }

    /// A recovery copy newer than the file itself.
    private func _recoveryIfNewer(than path: String) -> String? {
        let recovery = _recoveryPath(for: path)
        let fm = FileManager.default
        guard let r = try? fm.attributesOfItem(atPath: recovery)[.modificationDate] as? Date,
              let f = try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date, r > f else { return nil }
        return recovery
    }

    /// The unsaved workbook, beside its file; the file is not touched.
    private func _writeRecovery(for path: String) {
        _ = _grid?.commitEdit()
        wb.stashViewState()
        guard let data = try? Xlsx.write(wb.book) else { return }
        try? data.write(to: URL(fileURLWithPath: _recoveryPath(for: path)), options: .atomic)
    }
    #endif

    /// A file as bytes, from the browser's picker: a .docx or .pptx goes to
    /// its own shell with the same bytes.
    /// `recovered`: a browser tab's recovery copy, opened unsaved and already the page's row.
    /// `handle`: the page's handle on the picked file, which Save then writes back into.
    private func _open(_ name: String, data: Data, recovered: Bool = false, handle: Int? = nil) {
        // What the tab opens goes to the top of Recent (not a recovery copy: the page holds that already).
        if !recovered { _rememberInBrowser(name, data, handle: handle) }
        let kind = DocumentKind.kind(forPath: name)
        if kind != .workbook {
            PickedFile.hand(name, data, handle: handle)
            _w.onSwitch(kind, name)
            return
        }
        guard recovered else {
            if _load(data, from: name) { _browserHandle = handle }
            return
        }
        do { wb.load(try Workbook.open(data, name: name.lastPathComponent)) } catch {
            // A copy that does not read never blocks the next start.
            _dropBrowserCopy()
            return
        }
        session.path = name
        wb.markUnsaved()
        session.dirty = true
        _keptChanges = wb.dataRevision
        setState { _backstage = nil }
        _flash("Restored unsaved changes to \(name.lastPathComponent) — Save to keep them")
    }

    /// `path` is a file on disk natively, the picked file's name in a tab:
    /// what the window is called and what a save is named after.
    @discardableResult
    private func _load(_ data: Data, from path: String) -> Bool {
        do { wb.load(try Workbook.open(data, name: path.lastPathComponent)) } catch {
            _flash("Could not open \(path.lastPathComponent): it isn't a workbook Sheets can read")
            return false
        }
        session.path = path
        _browserHandle = nil
        session.dirty = false
        _remember(path)
        setState { _backstage = nil }
        _flash("Opened \(path.lastPathComponent)")
        return true
    }

    private func _save() {
        let own = session.path.map { ["xlsx", "csv", "tsv"].contains($0.pathExtension.lowercased()) } ?? false
        if let files = OfficeHost.browserFiles {
            // Back into the file it came from, where the browser gave us its
            // handle; else the browser's save picker; else a download, named
            // after the workbook (the browser decides where it goes).
            if let handle = _browserHandle, let path = session.path, own {
                _writeInBrowser(files, handle: handle, name: path.lastPathComponent)
            } else if files.canPickPlace {
                _saveAsInBrowser(files)
            } else {
                _saveTo(session.title.deletingPathExtension + ".xlsx")
            }
            return
        }
        guard let path = session.path, own else {
            setState { _backstage = .saveAs }
            return
        }
        _saveTo(path)
    }

    private func _saveTo(_ chosen: String) {
        let ext = chosen.pathExtension.lowercased()
        let path = ["xlsx", "csv", "tsv"].contains(ext) ? chosen : chosen + ".xlsx"
        let format = path.pathExtension.lowercased()
        do {
            guard let data = try _encoded(as: format) else { return }
            if let files = OfficeHost.browserFiles {
                // A tab: a download (Save without a save picker, or Backstage's name box).
                files.download(path.lastPathComponent, data)
                _browserSaved(path.lastPathComponent, data, handle: nil, revision: wb.dataRevision)
                return
            }
            // (WASI has no atomic write; a tab always has browserFiles and returned above.)
            #if os(WASI)
            try data.write(to: URL(fileURLWithPath: path))
            #else
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            #endif
            officeScene.documentSaved?(path)
            #if os(macOS)
            // What was kept for a crash is stale now: under the new name and the old one.
            try? FileManager.default.removeItem(atPath: _recoveryPath(for: path))
            if let old = session.path, old != path { try? FileManager.default.removeItem(atPath: _recoveryPath(for: old)) }
            #endif
            session.path = path
            _dropBrowserCopy()
            wb.markSaved()
            _remember(path)
            setState {
                session.dirty = false
                _backstage = nil
            }
            _flash(wb.book.sheets.count > 1 && format != "xlsx"
                   ? "Saved \(path.lastPathComponent) — CSV keeps only the active sheet"
                   : "Saved \(path.lastPathComponent)")
        } catch {
            _flash("Could not save \(path.lastPathComponent): \(plainFailure(error))")
        }
    }

    /// The workbook's bytes as `format` (xlsx, or the active sheet as csv/tsv), the cell being typed in first.
    private func _encoded(as format: String) throws -> Data? {
        _ = _grid?.commitEdit()
        wb.stashViewState()
        if format == "xlsx" { return try Xlsx.write(wb.book) }
        return Data(Csv.write(wb.sheet, book: wb.book, separator: format == "tsv" ? "\t" : ",").utf8)
    }

    // MARK: Saving in a browser tab (web-parity 4, as Writer)

    /// Save As through the browser's own picker: a place and a name, in a format Sheets writes (the workbook's
    /// own first).
    private func _saveAsInBrowser(_ files: OfficeHost.BrowserFiles) {
        _ = _grid?.commitEdit()
        let writable = ["xlsx", "csv", "tsv"]
        let ownExt = (session.path?.pathExtension.lowercased()).flatMap { writable.contains($0) ? $0 : nil } ?? "xlsx"
        let base = session.path.map { $0.lastPathComponent.deletingPathExtension } ?? session.title.deletingPathExtension
        files.pickPlace(base + "." + ownExt, [ownExt] + writable.filter { $0 != ownExt }) { [weak self] place in
            guard let self, self.mounted, let place else { return }
            self._writeInBrowser(files, handle: place.handle, name: place.name)
        }
    }

    private func _writeInBrowser(_ files: OfficeHost.BrowserFiles, handle: Int, name: String) {
        let ext = name.pathExtension.lowercased()
        let format = ["csv", "tsv"].contains(ext) ? ext : "xlsx"
        let data: Data
        do {
            guard let d = try _encoded(as: format) else { return }
            data = d
        } catch {
            _flash("Could not save \(name): \(plainFailure(error))")
            return
        }
        let revision = wb.dataRevision
        files.write(handle, data) { [weak self] ok in
            guard let self, self.mounted else { return }
            if ok {
                self._browserSaved(name, data, handle: handle, revision: revision)
            } else {
                self._flash("Could not save \(name): the browser did not allow writing to it")
            }
        }
    }

    /// Written or downloaded: the recovery copy goes, Recent gets the bytes, and Save writes back to `handle`.
    /// Changes made while the browser wrote keep the workbook unsaved.
    private func _browserSaved(_ name: String, _ data: Data, handle: Int?, revision: Int) {
        session.path = name
        _browserHandle = handle
        _dropBrowserCopy()
        let current = wb.dataRevision == revision
        if current { wb.markSaved() }
        _rememberInBrowser(name, data, handle: handle)
        setState {
            session.dirty = !current
            _backstage = nil
        }
        let csv = ["csv", "tsv"].contains(name.pathExtension.lowercased())
        _flash(wb.book.sheets.count > 1 && csv ? "Saved \(name) — CSV keeps only the active sheet" : "Saved \(name)")
    }

    /// A workbook opened or saved: natively its path goes to the top of Recent; in a tab the list is the page's.
    private func _remember(_ path: String) {
        if let browser = OfficeHost.browserRecent { _recent = browser.names(); return }
        _recent = OfficeRecent.remember(path, in: _recent)
    }

    /// A workbook opened or saved in a tab: the page keeps its bytes under its name, so Recent can reopen it.
    private func _rememberInBrowser(_ name: String, _ data: Data, handle: Int?) {
        guard let browser = OfficeHost.browserRecent else { return }
        browser.remember(name, data, handle)
        _recent = browser.names()
    }

    /// PDF or CSV of the active sheet (Excel's own default for both),
    /// beside the workbook or in Documents.
    private func _export(_ ext: String, share: Bool = false) {
        _ = _grid?.commitEdit()
        #if os(WASI)
        // Both are downloads, like a save.
        setState { _backstage = nil }
        if ext == "csv" {
            WebFiles.download(Data(Csv.write(wb.sheet, book: wb.book).utf8), as: session.title.deletingPathExtension + ".csv")
            _flash("Exported \(session.title.deletingPathExtension).csv")
        } else {
            let name = session.title.deletingPathExtension + ".pdf"
            _flash("Exporting \(name)…")
            Task { @MainActor [weak self] in
                guard let self, let grid = self._grid else { return }
                let ok = await grid.writePdf(to: name, title: self.session.title, filePath: self.session.path)
                self._flash(ok ? "Exported \(name)" : "Nothing to export on this sheet")
            }
        }
        return
        #else
        let base = session.path.map { $0.deletingPathExtension } ?? homeDirectory() + "/Documents/" + session.title.deletingPathExtension
        let target = base + "." + ext
        if let ask = share ? officeScene.shareRequested : officeScene.exportRequested {
            setState { _backstage = nil }
            ask(target.lastPathComponent, { [weak self] path, finished in
                guard let self else { finished(false); return }
                if ext == "csv" {
                    finished((try? Data(Csv.write(self.wb.sheet, book: self.wb.book).utf8)
                        .write(to: URL(fileURLWithPath: path))) != nil)
                } else {
                    Task { @MainActor [weak self] in
                        guard let self, let grid = self._grid else { finished(false); return }
                        finished(await grid.writePdf(to: path, title: self.session.title, filePath: self.session.path))
                    }
                }
            }, false) { [weak self] picked in
                if let picked { self?._flash("\(share ? "Shared" : "Exported") \(picked)") }
            }
            return
        }
        if ext == "csv" {
            // The active sheet, as Excel's CSV export (a copy: the workbook stays the document).
            setState { _backstage = nil }
            do {
                try Data(Csv.write(wb.sheet, book: wb.book).utf8).write(to: URL(fileURLWithPath: target))
                _flash("Exported \(target.lastPathComponent)")
            } catch {
                _flash("Could not export: \(error)")
            }
            return
        }
        setState { _backstage = nil }
        _flash("Exporting \(target.lastPathComponent)…")
        Task { @MainActor [weak self] in
            guard let self, let grid = self._grid else { return }
            let ok = await grid.writePdf(to: target, title: self.session.title, filePath: self.session.path)
            self._flash(ok ? "Exported \(target.lastPathComponent)" : "Nothing to export on this sheet")
        }
        #endif
    }

    /// File → Print: the shared Print dialog. Its page counts come first (a layout pass for each
    /// thing it can print), then it opens.
    private func _print() {
        _ = _grid?.commitEdit()
        setState { _backstage = nil }
        Task { @MainActor [weak self] in
            guard let self, let grid = self._grid else { return }
            let sel = self.wb.selection
            var kinds: [PrintWhat] = [.activeSheet, .entireWorkbook]
            if sel.area > 1 { kinds.append(.selection) }
            var counts: [Int] = []
            for k in kinds {
                let n = SheetJobBox(0)
                _ = await grid.writePdf(to: "", title: "", wholeBook: k == .entireWorkbook,
                                        selection: k == .selection ? sel : nil, countOnly: n)
                counts.append(n.value)
            }
            self.setState { self._printKinds = kinds; self._printCounts = counts; self._printOpen = true }
        }
    }

    /// The shared dialog's hooks for this workbook: Active sheet, Entire workbook and (when
    /// more than a cell is selected) Selection, each with its own page count.
    var _printHooks: PrintHooks {
        let kinds = _printKinds, counts = _printCounts
        return PrintHooks(unit: "Pages", total: max(1, counts.first ?? 1), current: 1,
                          totals: counts.map { max(1, $0) },
                          outputs: kinds.map(\.label), hostCanPrint: hostCanPrintPDF,
                          print: { [weak self] pages, output in
            guard let self, kinds.indices.contains(output) else { return "Nothing to print" }
            return self._print(kinds[output], pages: pages)
        })
    }

    private func _print(_ what: PrintWhat, pages: [Int]) -> String {
        // A host that prints bytes (the browser) gets the PDF itself; one
        // that prints files gets a file in the temporary folder.
        let bytes = hostPrintPDFBytes
        #if os(WASI)
        let path = "/print/" + session.title.deletingPathExtension + ".pdf"
        #else
        let path = NSTemporaryDirectory() + "sheets-print-\(ProcessInfo.processInfo.processIdentifier).pdf"
        #endif
        let name = session.title.deletingPathExtension + ".pdf"
        Task { @MainActor [weak self] in
            guard let self, let grid = self._grid else { return }
            guard await grid.writePdf(to: path, title: self.session.title, filePath: self.session.path,
                                      wholeBook: what == .entireWorkbook, selection: what == .selection ? self.wb.selection : nil,
                                      pages: pages, deliver: bytes.map { send in { data in send(data, name) } }) else {
                self._flash("Nothing to print on this sheet")
                return
            }
            if bytes != nil { return }
            if let print = hostPrintPDF { print(path) } else { self._flash("No print dialog on this host") }
        }
        return ""
    }

    // MARK: Formula bar

    private func _formulaBar(_ fluent: FluentThemeData) -> Widget {
        let line = fluent.resources.dividerStrokeColorDefault
        return DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.solidBackgroundFillColorBase,
                border: Border(bottom: BorderSide(color: line, width: 1))),
            child: Padding(padding: EdgeInsets(left: 8, top: 4, right: 8, bottom: 4), child: Row(
                crossAxisAlignment: .center, children: [
                    SizedBox(width: 96, height: 28, child: FluentTextBox(
                        controller: _nameBox, semanticLabel: "Name Box",
                        onSubmitted: { [weak self] text in self?._goTo(text) })),
                    Padding(key: ValueKey("name-box-list"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child: Chrome.menu(nil, nil, fluent,
                        wb.definedNameEntries().prefix(60).map { e in (e.name, { [weak self] in self?._goTo(e.name) }) }
                            + (wb.definedNameEntries().isEmpty ? [("No names defined", {})] : []))),
                    Chrome.gap(6),
                    Chrome.icon(FluentSystemIcons.close, "Cancel", fluent, enabled: _formulaEditing || _grid?.edit != nil) { [weak self] in
                        self?._cancelFormula()
                    },
                    Chrome.icon(FluentSystemIcons.check, "Enter", fluent, enabled: _formulaEditing || _grid?.edit != nil) { [weak self] in
                        self?._commitFormula(self?._formula.text ?? "")
                    },
                    Text("fx", style: fluent.typography.bodyStrong?.copyWith(fontStyle: .italic)),
                    Chrome.gap(8),
                    Expanded(child: SizedBox(width: nil, height: 28, child: FluentTextBox(
                        controller: _formula, semanticLabel: "Formula Bar",
                        onChanged: { [weak self] text in
                            guard let self, !self._settingFormula else { return }
                            self._formulaEditing = true
                            self._grid?.setEditText(text)
                        },
                        onSubmitted: { [weak self] text in self?._commitFormula(text) },
                        onFocusChanged: { [weak self] focused in
                            guard let self, !focused, self._formulaEditing else { return }
                            // Leaving the bar keeps what was typed, as Excel does on a click elsewhere.
                            self._commitFormula(self._formula.text, move: false)
                        }))),
                ])))
    }

    private func _commitFormula(_ text: String, move: Bool = true) {
        _formulaEditing = false
        if let grid = _grid, grid.edit != nil {
            grid.setEditText(text)
            grid.commitEdit()
        } else {
            wb.setInput(text, at: wb.active)
        }
        if move { wb.advance(rows: 1, cols: 0); _grid?.reveal(wb.active) }
        _grid?.focus.requestFocus()
        _syncBars()
    }

    private func _cancelFormula() {
        _formulaEditing = false
        _grid?.cancelEdit()
        _grid?.focus.requestFocus()
        _syncBars()
        setState {}
    }

    /// The name box: an address (B7), a range (A1:C10), or a sheet's cell.
    private func _goTo(_ text: String) {
        let t = text.trimmingWhitespace()
        if let r = CellRange(t.uppercased()) {
            wb.select(range: r, active: r.topLeft)
            _grid?.reveal(r.topLeft)
        } else if let bang = t.lastIndex(of: "!"), let si = wb.book.sheet(named: String(t[..<bang]).trimming(charactersIn: "'")),
                  let r = CellRange(String(t[t.index(after: bang)...]).uppercased()) {
            wb.activeSheet = si
            wb.select(range: r, active: r.topLeft)
            _grid?.reveal(r.topLeft)
        } else if let target = wb.nameTarget(t) {
            wb.activeSheet = target.sheet
            wb.select(range: target.range, active: target.range.topLeft)
            _grid?.reveal(target.range.topLeft)
        } else if let problem = wb.defineNameForSelection(t) {
            _flash(problem.message)
        } else {
            _flash("Named the selection “\(t)”")
        }
        _grid?.focus.requestFocus()
        _syncBars()
    }

    // MARK: Sheet tabs

    private func _sheetTabs(_ fluent: FluentThemeData) -> Widget {
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        var tabs: [Widget] = []
        for (i, ws) in wb.book.sheets.enumerated() where !ws.hidden {
            let on = i == wb.activeSheet
            if _renaming == i {
                tabs.append(SizedBox(width: 120, height: 26, child: FluentTextBox(
                    controller: _renameText,
                    onSubmitted: { [weak self] name in self?._finishRename(i, name) },
                    autofocus: true,
                    onFocusChanged: { [weak self] f in if !f { self?._finishRename(i, self?._renameText.text ?? "") } })))
                continue
            }
            let label = Text(ws.name, style: (on ? fluent.typography.bodyStrong : fluent.typography.body)?.copyWith(
                color: on ? accent : fluent.resources.textFillColorPrimary))
            // A right click opens the sheet menu for that tab, as Excel's
            // tabs do; it had nothing.
            tabs.append(SheetTabProbe(index: i, probes: _tabProbes, child: Listener(
                onPointerDown: { [weak self] e in
                    guard let self else { return }
                    if e.buttons & kPrimaryMouseButton != 0 { self._tabDrag = (i, Double(e.position.dx), false) }
                    guard e.buttons & kSecondaryMouseButton != 0, let context = self.context else { return }
                    _ = self._grid?.commitEdit()
                    self.wb.activeSheet = i
                    self._syncBars()
                    let items: [MenuFlyoutItemBase] = self._sheetMenu(i).map { text, action in MenuFlyoutItem(text: Text(text), onPressed: action) }
                    self._contextMenu.showFlyout(in: context, at: e.position) { _ in MenuFlyout(items: items) }
                },
                onPointerMove: { [weak self] e in
                    guard let self, let d = self._tabDrag, !d.moved, abs(Double(e.position.dx) - d.x) > SheetTabDrag.threshold else { return }
                    self._tabDrag?.moved = true
                },
                onPointerUp: { [weak self] e in
                    guard let self, let d = self._tabDrag else { return }
                    self._tabDrag = nil
                    guard d.moved else { return }
                    let spans = self._tabProbes.spans(self.wb.visibleSheets)
                    guard let to = SheetTabDrag.target(spans: spans, x: Double(e.position.dx)) else { return }
                    if let why = self.wb.dropTab(from: d.from, to: to, copy: self._grid?.controlHeld == true) { self._flash(why) }
                },
                child: FlatButton(
                child: Padding(padding: EdgeInsets(left: 12, top: 0, right: 12, bottom: 0), child: Column(
                    mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                        label,
                        Chrome.vgap(2),
                        SizedBox(width: 24, height: 2, child: ColoredBox(
                            color: ws.tabColor.flatMap { UInt32($0.suffix(6), radix: 16) }.map { Color(Int64(0xFF000000 | $0)) }
                                ?? (on ? accent : Color(0x00000000)), child: SizedBox(expand: ()))),
                    ])),
                tip: on ? "Double-click to rename" : nil, checked: on || (wb.isGrouped && wb.groupedSheets.contains(i)), width: nil, height: 28,
                action: { [weak self] in self?._tabClicked(i) }))))
        }
        tabs.append(Chrome.icon(FluentSystemIcons.add, "New sheet", fluent) { [weak self] in self?.wb.addSheet() })
        tabs.append(Chrome.menu(nil, Icon(FluentSystemIcons.moreHorizontal, size: Chrome.iconSize,
                                          color: fluent.resources.textFillColorPrimary), fluent, _sheetMenu(wb.activeSheet), tip: "Sheet Menu"))
        return DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.solidBackgroundFillColorBase,
                border: Border(top: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 8, top: 1, right: 8, bottom: 1), child: Row(
                crossAxisAlignment: .center, children: tabs)))
    }

    /// What can be done to sheet `i`: the tab's right-click menu and the
    /// "…" beside the tabs.
    func _tabMenuTitles(_ i: Int) -> [String] { _sheetMenu(i).map(\.0) }
    /// Runs the tab menu item titled `title` for sheet `i` (tests).
    func _runTabMenu(_ i: Int, _ title: String) { _sheetMenu(i).first { $0.0 == title }?.1() }

    private func _sheetMenu(_ i: Int) -> [(String, () -> Void)] {
        var menu: [(String, () -> Void)] = [
            ("Rename Sheet", { [weak self] in self?._startRename(i) }),
            ("Insert Sheet", { [weak self] in self?.wb.addSheet() }),
            ("Delete Sheet", { [weak self] in self?.wb.requestDeleteSheet(i) }),
            ("Move or Copy…", { [weak self] in self?.setState { self?._moveCopyFor = i } }),
            ("Tab Color…", { [weak self] in self?.setState { self?._tabColorFor = i } }),
            // Excel's tab menu protects the tab it was opened on.
            (wb.protection(i) != nil ? "Unprotect Sheet…" : "Protect Sheet…", { [weak self] in
                guard let self else { return }
                if self.wb.activeSheet != i { self.wb.activeSheet = i }
                self._command(.protectSheetDialog)
            }),
            ("Hide Sheet", { [weak self] in self?.wb.hideSheet(i) }),
            ("Select All Sheets", { [weak self] in self?.wb.selectAllSheets() }),
        ]
        if wb.isGrouped { menu.append(("Ungroup Sheets", { [weak self] in self?.wb.ungroupSheets() })) }
        // Hidden sheets can be shown again; very hidden ones only by code, as in Excel.
        for (j, ws) in wb.book.sheets.enumerated() where ws.hidden && !ws.veryHidden {
            menu.append(("Unhide “\(ws.name)”", { [weak self] in self?.wb.unhideSheet(j) }))
        }
        return menu
    }

    private func _tabClicked(_ i: Int) {
        _ = _grid?.commitEdit()
        // Double click renames (by hand: onDoubleTap kills taps on DRM).
        if let last = _lastTabClick, last.index == i, Date().timeIntervalSince(last.at) < 0.4 {
            _lastTabClick = nil
            _startRename(i)
            return
        }
        _lastTabClick = (i, Date())
        // Ctrl/⌘-click adds the sheet to the group; a plain click on a sheet
        // outside it ends the group, on one inside it keeps it, as Excel.
        if _grid?.controlHeld == true { wb.groupSheet(i, add: true) }
        else if !wb.groupedSheets.contains(i) { wb.ungroupSheets() }
        wb.activeSheet = i
        _grid?.focus.requestFocus()
        _syncBars()
    }

    private func _startRename(_ i: Int) {
        // The whole name selected, as Excel's rename starts: typing replaces it.
        let name = wb.book.sheets[i].name
        _renameText.value = TextEditingValue(text: name, selection: TextSelection(baseOffset: 0, extentOffset: name.count))
        setState { _renaming = i }
    }

    private func _finishRename(_ i: Int, _ name: String) {
        guard _renaming == i else { return }
        _renaming = nil
        if name != wb.book.sheets[i].name, !wb.renameSheet(i, name) {
            _flash("A sheet name must be 1–31 characters, unique, and without [ ] : * ? / \\")
        }
        setState {}
        _grid?.focus.requestFocus()
    }

    // MARK: Status bar

    private func _statusBar(_ fluent: FluentThemeData) -> Widget {
        let caption = fluent.typography.caption
        let dim = caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        var left: [Widget] = [Text(_grid?.edit != nil ? (_grid!.edit!.enterMode ? "Enter" : "Edit") : "Ready", style: caption)]
        if !wb.engine.circular.isEmpty {
            left.append(Chrome.gap(20))
            let first = wb.engine.circular.sorted { ($0.sheet, $0.cell) < ($1.sheet, $1.cell) }.first!
            left.append(Text("Circular References: \(first.cell.a1)", style: caption))
        }
        if let summary = wb.filterSummary {
            left.append(Chrome.gap(20))
            left.append(Text(summary, style: caption))
        }
        if let message = _status {
            left.append(Chrome.gap(20))
            left.append(Text(message, style: dim))
        }
        var right: [Widget] = []
        for (f, value) in _statusFigures() where Self.statusShown.contains(f) {
            guard let value else { continue }
            right.append(Text("\(f.label): \(value)", style: caption))
            right.append(Chrome.gap(16))
        }
        right += [
            Chrome.icon(FluentSystemIcons.zoomOut, "Zoom Out", fluent) { [weak self] in self?._command(.zoom(1 / 1.1)) },
            SizedBox(width: 44, height: nil, child: Text("\(Int((_zoom * 100).rounded()))%", style: caption)),
            Chrome.icon(FluentSystemIcons.zoomIn, "Zoom In", fluent) { [weak self] in self?._command(.zoom(1.1)) },
        ]
        return DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.solidBackgroundFillColorBase,
                border: Border(top: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            // A right click chooses which figures show, as Excel's Customize Status Bar does.
            child: Listener(onPointerDown: { [weak self] e in
                guard let self, e.buttons & kSecondaryMouseButton != 0, let context = self.context else { return }
                let figures = self._statusFigures()
                let items: [MenuFlyoutItemBase] = figures.map { f, value in
                    ToggleMenuFlyoutItem(text: Text(f.menuTitle), trailing: Text(value ?? "", style: dim),
                                         isChecked: Self.statusShown.contains(f),
                                         onChanged: { [weak self] _ in self?._toggleStatusFigure(f) })
                }
                self._contextMenu.showFlyout(in: context, at: e.position) { _ in MenuFlyout(items: items) }
            }, behavior: .translucent, child: Padding(padding: EdgeInsets(left: 12, top: 2, right: 8, bottom: 2), child: Row(
                crossAxisAlignment: .center,
                children: left + [Expanded(child: SizedBox(width: 0, height: 0, child: nil))] + right))))
    }

    /// A figure the status bar can show for a selection of more than one cell, in Excel's order.
    enum StatusFigure: CaseIterable {
        case average, count, numericalCount, min, max, sum
        var label: String {
            switch self {
            case .average: return "Average"
            case .count: return "Count"
            case .numericalCount: return "Numerical Count"
            case .min: return "Min"
            case .max: return "Max"
            case .sum: return "Sum"
            }
        }
        var menuTitle: String {
            switch self {
            case .min: return "Minimum"
            case .max: return "Maximum"
            default: return label
            }
        }
    }

    /// The figures shown, for every workbook in the app (Excel keeps this per user, not per file):
    /// Average, Count and Sum by default.
    static var statusShown: Set<StatusFigure> = [.average, .count, .sum]

    /// Each figure and its value for the selection, nil when it has none (a single cell,
    /// no values, or no numbers for the number figures).
    func _statusFigures() -> [(StatusFigure, String?)] {
        let s = wb.selection.isSingle ? nil : wb.selectionStats
        return StatusFigure.allCases.map { f in
            guard let s, s.count > 0 else { return (f, nil) }
            switch f {
            case .average: return (f, s.average.map { NumberFormat.general($0) })
            case .count: return (f, "\(s.count)")
            case .numericalCount: return (f, "\(s.numbers)")
            case .min: return (f, s.min.map { NumberFormat.general($0) })
            case .max: return (f, s.max.map { NumberFormat.general($0) })
            case .sum: return (f, s.numbers > 0 ? NumberFormat.general(s.sum) : nil)
            }
        }
    }

    /// The status bar text as shown (tests).
    func _statusBarFigures() -> [String] {
        _statusFigures().compactMap { f, v in Self.statusShown.contains(f) ? v.map { "\(f.label): \($0)" } : nil }
    }

    /// Shows or hides one figure (the status bar's right-click menu).
    func _toggleStatusFigure(_ f: StatusFigure) {
        setState { if Self.statusShown.contains(f) { Self.statusShown.remove(f) } else { Self.statusShown.insert(f) } }
    }

    // MARK: Build

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let title = "\(session.title)\(session.dirty ? " •" : "") — Sheets"
        if title != _windowTitle {
            _windowTitle = title
            hostSetWindowTitle?(title)
        }
        let column: [Widget] = [
            TitleRow(session: session, searchController: _search, onSearch: { [weak self] q in
                guard let self else { return }
                self._findQuery.text = q
                self._openFind(replace: false)
            }),
            Ribbon(session: session, tab: _tab, collapsed: _ribbonCollapsed,
                   onTab: { [weak self] t in self?.setState { self?._tab = t } },
                   onCollapse: { [weak self] in self?.setState { self?._ribbonCollapsed.toggle() } }),
        ]
        + (wb.pendingSheetDelete.map { i in [ConfirmBar(
            message: "Delete “\(wb.book.sheets.indices.contains(i) ? wb.book.sheets[i].name : "")”? Its cells and objects go with it (Undo brings it back).",
            action: "Delete sheet", onConfirm: { [weak self] in self?.wb.confirmSheetDelete() },
            onCancel: { [weak self] in self?.wb.cancelSheetDelete() })] } ?? []) + [
            _formulaBar(fluent),
            Expanded(child: Row(crossAxisAlignment: .stretch, children: [
                Expanded(child: KeyboardPage(focus: { [weak self] in self?._grid?.focus.requestFocus() }, child: SheetGrid(
                key: _gridKey, controller: wb, zoom: _zoom,
                onEditText: { [weak self] text in
                    // The bar over the keyboard is a formula's keys while a cell is typed in, and number commands otherwise.
                    if let self, self._cellEditing != (text != nil) {
                        self._cellEditing = text != nil
                        self._publishToolbar()
                    }
                    guard let self, !self._formulaEditing else { return }
                    self._setFormulaText(text ?? self.wb.input(self.wb.active))
                    self.setState {}
                },
                onShortcut: { [weak self] letter, chords in self?._shortcut(letter, chords) ?? false },
                onStatus: { [weak self] m in self?._flash(m) },
                onContextMenu: { [weak self] point, area in self?._showContextMenu(at: point, area) },
                onFilterMenu: { [weak self] point, col in self?._showFilterMenu(at: point, col: col) },
                onListMenu: { [weak self] point, cell, choices in self?._showListMenu(at: point, cell: cell, choices) },
                onPasteOptions: { [weak self] point in self?._showPasteOptions(at: point) },
                onZoom: { [weak self] f in self?.setState { self?._zoom = max(0.25, min(4, (self?._zoom ?? 1) * f)) } }))),
                PivotFieldsPane(controller: wb, onChange: { [weak self] in self?.setState {} },
                                onValueSettings: { [weak self] k in self?.setState { self?._pvValueOpen = k } },
                                onGroup: { [weak self] f in self?.setState { self?._pvGroupOpen = f } }),
            ])),
            _sheetTabs(fluent),
            _statusBar(fluent),
        ]
        let window = ColoredBox(color: fluent.scaffoldBackgroundColor,
                                child: Column(crossAxisAlignment: .stretch, children: column))
        var layers: [Widget] = [window]
        let _names = SheetPrintLayout.printNames(wb.book, sheet: wb.activeSheet)
        if _pageSetupOpen {
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: PageSetupPanel(
                        form: PageSetupForm(SheetPrintSetup.read(wb.sheet), paper: wb.paperNumber,
                                            area: _names.areas.first, titleRows: _names.titleRows, titleCols: _names.titleCols),
                        onApply: { [weak self] c, n in self?.wb.setPageSetup(c, printNames: n) },
                        onClose: { [weak self] in
                            self?.setState { self?._pageSetupOpen = false }
                            self?._grid?.focus.requestFocus()
                        })))
        }
        if _cfOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ConditionalFormatDialog(
                controller: wb, onClose: { [weak self] in
                    self?.setState { self?._cfOpen = false }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if _cfRulesOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ManageRulesDialog(
                controller: wb, onClose: { [weak self] in
                    self?.setState { self?._cfRulesOpen = false }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if _validationOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ValidationDialog(
                controller: wb, onClose: { [weak self] in
                    self?.setState { self?._validationOpen = false }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if _seriesOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SeriesDialog(
                controller: wb, onClose: { [weak self] in
                    self?.setState { self?._seriesOpen = false }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if _consOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ConsolidateDialog(
                controller: wb, onClose: { [weak self] in
                    self?.setState { self?._consOpen = false }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if let open = _alertOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ValidationAlertDialog(
                alert: open.alert, onChoice: { [weak self] choice in
                    self?.setState { self?._alertOpen = nil }
                    open.answer(choice)
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if _scnOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ScenarioDialog(
                controller: wb, onClose: { [weak self] in
                    self?.setState { self?._scnOpen = false }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if let i = _chartSeriesOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ChartSeriesDialog(
                controller: wb, index: i, onClose: { [weak self] in
                    self?.setState { self?._chartSeriesOpen = nil }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if let i = _chartAxisOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ChartAxisDialog(
                controller: wb, index: i, onClose: { [weak self] in
                    self?.setState { self?._chartAxisOpen = nil }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if let i = _chartLabelsOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ChartLabelsDialog(
                controller: wb, index: i, onClose: { [weak self] in
                    self?.setState { self?._chartLabelsOpen = nil }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if let kind = _chartForm {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ChartFormDialog(
                controller: wb, kind: kind, onClose: { [weak self] in
                    self?.setState { self?._chartForm = nil }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if _sparklineOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SparklineDialog(
                controller: wb, create: _sparklineKind, onClose: { [weak self] in
                    self?.setState { self?._sparklineOpen = false }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if let i = _chartColorsOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ChartColorsDialog(
                controller: wb, index: i, onClose: { [weak self] in
                    self?.setState { self?._chartColorsOpen = nil }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if let i = _chartTitlesOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ChartTitlesDialog(
                controller: wb, index: i, onClose: { [weak self] in
                    self?.setState { self?._chartTitlesOpen = nil }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if _dtOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: DataTableDialog(
                controller: wb, onClose: { [weak self] in
                    self?.setState { self?._dtOpen = false }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if _goalOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: GoalSeekDialog(
                controller: wb, onClose: { [weak self] in
                    self?.setState { self?._goalOpen = false }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if let open = _dupOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: RemoveDuplicatesDialog(
                controller: wb, range: open.range, hasHeader: open.hasHeader, onClose: { [weak self] in
                    self?.setState { self?._dupOpen = nil }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if let open = _ttcOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: TextToColumnsDialog(
                controller: wb, range: open, onClose: { [weak self] in
                    self?.setState { self?._ttcOpen = nil }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if let open = _pvGroupOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: PivotGroupDialog(
                controller: wb, field: open, onClose: { [weak self] in
                    self?.setState { self?._pvGroupOpen = nil }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if let open = _pvValueOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: PivotValueFieldDialog(
                controller: wb, index: open, onClose: { [weak self] in
                    self?.setState { self?._pvValueOpen = nil }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if let open = _subOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SubtotalDialog(
                controller: wb, range: open, onClose: { [weak self] in
                    self?.setState { self?._subOpen = nil }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if let open = _sortOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SortDialog(
                controller: wb, range: open.range, hasHeader: open.hasHeader, onClose: { [weak self] in
                    self?.setState { self?._sortOpen = nil }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if _pivotOpen {
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: PivotDialog(
                controller: wb, onClose: { [weak self] in
                    self?.setState { self?._pivotOpen = false }
                    self?._grid?.focus.requestFocus()
                })))
        }
        if _tableOpen {
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: TableDialog(
                controller: wb, onClose: { [weak self] in
                    self?.setState { self?._tableOpen = false }
                    self?._grid?.focus.requestFocus()
                })))
        }
        if let open = _filterOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: FilterDialog(
                controller: wb, col: open.col, kind: open.kind, onClose: { [weak self] in
                    self?.setState { self?._filterOpen = nil }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if _createNamesOpen {
            return Stack(children: [window, Positioned(left: 0, top: 0, right: 0, bottom: 0, child: CreateNamesDialog(
                controller: wb, onClose: { [weak self] in
                    self?.setState { self?._createNamesOpen = false }
                    self?._grid?.focus.requestFocus()
                }))])
        }
        if _namesOpen {
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: NameManagerDialog(
                controller: wb, onClose: { [weak self] in
                    self?.setState { self?._namesOpen = false }
                    self?._grid?.focus.requestFocus()
                })))
        }
        if let workbook = _protectOpen {
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ProtectDialog(
                controller: wb, workbook: workbook, onClose: { [weak self] in
                    self?.setState { self?._protectOpen = nil }
                    self?._grid?.focus.requestFocus()
                })))
        }
        if _shortcutsOpen {
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: ShortcutListDialog(
                table: ShortcutTable.sheets, onClose: { [weak self] in
                    self?.setState { self?._shortcutsOpen = false }
                    self?._grid?.focus.requestFocus()
                })))
        }
        if _printOpen {
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: PrintDialog(
                hooks: _printHooks,
                onClose: { [weak self] in
                    self?.setState { self?._printOpen = false }
                    self?._grid?.focus.requestFocus()
                })))
        }
        if let i = _tabColorFor, wb.book.sheets.indices.contains(i) {
            let cur = wb.book.sheets[i].tabColor.flatMap { UInt32($0.suffix(6), radix: 16) }
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: TabColorPanel(
                sheetName: wb.book.sheets[i].name, current: cur,
                onPick: { [weak self] c in self?.wb.setTabColor(i, c.map { v -> String in let h = String(v, radix: 16, uppercase: true); return "FF" + String(repeating: "0", count: max(0, 6 - h.count)) + h }) },
                onClose: { [weak self] in self?.setState { self?._tabColorFor = nil }; self?._grid?.focus.requestFocus() })))
        }
        if let i = _moveCopyFor, wb.book.sheets.indices.contains(i) {
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: MoveCopyPanel(
                sheetName: wb.book.sheets[i].name, sheets: wb.book.sheets.map(\.name), canCopy: wb.copyBlocker(i),
                onDone: { [weak self] before, copy in
                    guard let self else { return }
                    if copy { self.wb.copySheet(i, at: before) }
                    else { self.wb.moveSheet(i, to: before > i ? before - 1 : before) }
                },
                onClose: { [weak self] in self?.setState { self?._moveCopyFor = nil }; self?._grid?.focus.requestFocus() })))
        }
        if _pasteOpen, _backstage == nil {
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: PasteSpecialDialog(
                onApply: { [weak self] how in self?._grid?.paste(how) },
                onClose: { [weak self] in self?._closePasteSpecial() })))
        }
        if let insert = _cellsDialog, _backstage == nil {
            layers.append(InsertDeleteCellsDialog(
                insert: insert,
                onApply: { [weak self] c in self?.wb.applyCells(insert: insert, c) },
                onClose: { [weak self] in self?.setState { self?._cellsDialog = nil }; self?._grid?.focus.requestFocus() }))
        }
        if let kind = _sizeDialog, _backstage == nil {
            let sh = wb.sheet
            let start: Double
            switch kind {
            case .rowHeight: start = sh.rowHeight(wb.selection.top)
            case .columnWidth: start = Xlsx._displayChars(points: sh.colWidth(wb.selection.left), digit: sh.digitWidth)
            case .defaultWidth: start = Xlsx._displayChars(points: sh.defaultColWidthPt, digit: sh.digitWidth)
            }
            layers.append(SizeDialog(
                title: kind.title, unit: kind.unit, start: start,
                onApply: { [weak self] v in
                    switch kind {
                    case .rowHeight: self?.wb.setRowHeights(v)
                    case .columnWidth: self?.wb.setColumnWidths(Xlsx._pointsForDisplayChars(v, digit: sh.digitWidth))
                    case .defaultWidth: self?.wb.setDefaultColumnWidth(Xlsx._pointsForDisplayChars(v, digit: sh.digitWidth))
                    }
                },
                onClose: { [weak self] in self?.setState { self?._sizeDialog = nil }; self?._grid?.focus.requestFocus() }))
        }
        if _findOpen, _backstage == nil {
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: FindReplaceDialog(
                initialQuery: _findQuery.text, hooks: _findHooks, onClose: { [weak self] in self?._closeFind() })))
        }
        if _symbolOpen, _backstage == nil {
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: SymbolPicker(
                hooks: SymbolHooks(fonts: ["(current font)"], insert: { [weak self] text, _ in self?._grid?.insertSymbol(text) }),
                onClose: { [weak self] in
                    self?.setState { self?._symbolOpen = false }
                    self?._grid?.focus.requestFocus()
                })))
        }
        if _altOpen, let i = wb.selectedDrawing, wb.sheet.drawings.indices.contains(i) {
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: AltTextDialog(
                initial: wb.sheet.drawings[i].descr ?? "",
                title: wb.sheet.drawings[i].title ?? "",
                onApply: { [weak self] text, title in
                    self?.wb.setDrawingAlt(i, text, title: title)
                    self?.setState { self?._altOpen = false }
                    self?._grid?.focus.requestFocus()
                },
                onCancel: { [weak self] in self?.setState { self?._altOpen = false }; self?._grid?.focus.requestFocus() })))
        }
        if _linkOpen {
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: HyperlinkDialog(
                hooks: wb.hyperlinkHooks(flash: { [weak self] in self?._flash($0) }),
                onClose: { [weak self] in self?.setState { self?._linkOpen = false }; self?._grid?.focus.requestFocus() })))
        }
        if let fill = _moreColorsFill {
            let st = wb.style(at: wb.selection.topLeft)
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: CustomColorDialog(
                initial: (fill ? st.fill : st.color) ?? (fill ? 0xFFFFFF : 0),
                onOK: { [weak self] rgb in
                    self?.wb.setStyle { if fill { $0.fill = rgb } else { $0.color = rgb } }
                    self?.setState { self?._moreColorsFill = nil }; self?._grid?.focus.requestFocus()
                },
                onCancel: { [weak self] in self?.setState { self?._moreColorsFill = nil }; self?._grid?.focus.requestFocus() })))
        }
        if _lineColorOpen {
            layers.append(Positioned(left: 0, top: 0, right: 0, bottom: 0, child: CustomColorDialog(
                initial: wb.borderPenColor ?? 0,
                onOK: { [weak self] rgb in
                    self?.wb.borderPenColor = rgb
                    self?.setState { self?._lineColorOpen = false }; self?._grid?.focus.requestFocus()
                },
                onCancel: { [weak self] in self?.setState { self?._lineColorOpen = false }; self?._grid?.focus.requestFocus() })))
        }
        if layers.count > 1, _backstage == nil { return Stack(children: layers) }
        if _formatOpen, _backstage == nil {
            return Stack(children: layers + [
                { () -> Widget in
                    let d = FormatCellsDialog(
                        start: wb.formatCellsStart,
                        onApply: { [weak self] edit in self?.wb.formatCells(edit) },
                        onClose: { [weak self] in self?._closeFormatCells() })
                    d.startTab = _formatTab
                    return d
                }(),
            ])
        }
        guard let page = _backstage else { return layers.count == 1 ? window : Stack(children: layers) }
        return Stack(children: layers + [
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Backstage(
                session: session, page: page, recent: _recent, notice: _status,
                onPage: { [weak self] p in self?.setState { self?._backstage = p } },
                onClose: { [weak self] in
                    self?.setState { self?._backstage = nil }
                    self?._grid?.focus.requestFocus()
                },
                onOpenPath: { [weak self] path in self?._openFromPanel(path) },
                onSavePath: { [weak self] path in self?._saveTo(path) },
                onPicturePath: { [weak self] path in self?._insertPicture(path) }, scene: officeScene)),
        ])
    }

    /// ⌘S, ⌘O, ⌘N, ⌘P — the window's chords, which the grid passes up.
    private func _shortcut(_ letter: Character, _ chords: KeyChordTracker) -> Bool {
        switch letter {
        case "s":
            if chords.shift { setState { _backstage = .saveAs } } else { _save() }
            return true
        case "o": session.onOpen?(); return true   // the picker in a tab, Backstage natively
        case "n": session.replacing { [weak self] in self?._newWorkbook() }; return true
        case "p": _print(); return true
        case "/": session.onShortcuts?(); return true
        case "f": _openFind(replace: false); return true
        case "v" where chords.alt && _grid?.edit == nil: _openPasteSpecial(); return true
        case "1" where _grid?.edit == nil: _openFormatCells(); return true
        case "+" where _grid?.edit == nil: _openCellsDialog(insert: true); return true
        case "-" where _grid?.edit == nil: _openCellsDialog(insert: false); return true
        case "h": _openFind(replace: true); return true
        case "l" where chords.shift: wb.toggleAutoFilter(); return true
        // Excel for Mac's Group and Ungroup.
        case "k" where !chords.shift && _grid?.edit == nil: setState { _linkOpen = true }; return true
        case "k" where chords.shift: wb.group(true); return true
        case "j" where chords.shift: wb.group(false); return true
        case "\u{1B}":
            if _pageSetupOpen { setState { _pageSetupOpen = false }; return true }
            if _symbolOpen { setState { _symbolOpen = false }; _grid?.focus.requestFocus(); return true }
            // Esc leaves the File page, as in Word and PowerPoint.
            if _backstage != nil { setState { _backstage = nil }; return true }
            return false
        default: return false
        }
    }

    // MARK: Paste Special
    func _openPasteSpecial() {
        setState { _pasteOpen = true }
    }

    private func _closePasteSpecial() {
        guard _pasteOpen else { return }
        setState { _pasteOpen = false }
        _grid?.focus.requestFocus()
    }

    // MARK: Insert / Delete cells, sizes
    /// Ctrl++ / Ctrl+-: whole rows or columns act at once; a block of cells asks which way to shift.
    func _openCellsDialog(insert: Bool) {
        let r = wb.selection
        let wholeRows = r.left == 0 && r.right >= CellAddress.maxCols - 1
        let wholeCols = r.top == 0 && r.bottom >= CellAddress.maxRows - 1
        if wholeRows || wholeCols {
            wb.applyCells(insert: insert, wholeRows ? .entireRow : .entireColumn)
        } else {
            setState { _cellsDialog = insert }
        }
    }

    func _openSizeDialog(_ kind: SizeKind) { setState { _sizeDialog = kind } }

    // MARK: Format Cells
    func _openFormatCells(tab: Int = 0) {
        if wb.refuses("formatCells") { return }
        setState { _formatOpen = true; _formatTab = tab }
    }

    private func _closeFormatCells() {
        guard _formatOpen else { return }
        setState { _formatOpen = false }
        _grid?.focus.requestFocus()
    }

    // MARK: Find

    private func _openFind(replace: Bool) {
        setState { _findOpen = true }
    }

    private func _closeFind() {
        guard _findOpen else { return }
        setState { _findOpen = false }
        _grid?.focus.requestFocus()
    }

    private var _findHooks: FindHooks {
        func status(_ found: Bool) -> String {
            if found { _grid?.reveal(wb.active) }
            return found ? "" : "No matches"
        }
        func look(_ w: FindWhere) -> FindLookIn { FindLookIn(rawValue: w.lookIn) ?? .formulas }
        // Excel's Replace tab looks in formulas only.
        let formulasOnly = "Replace looks in formulas: set Look in to Formulas"
        var hooks = FindHooks(
            findNext: { [unowned self] p, w, back in
                let found = status(wb.findNext(p, scope: w.scope, lookIn: look(w), byColumns: w.byColumns, backwards: back))
                guard found.isEmpty, let at = wb.findPosition(p, scope: w.scope, lookIn: look(w), byColumns: w.byColumns) else { return found }
                return "\(at.index) of \(at.total)"
            },
            replace: { [unowned self] p, template, w in
                guard look(w) == .formulas else { return formulasOnly }
                return status(wb.replaceCurrent(p, with: template, scope: w.scope, byColumns: w.byColumns))
            },
            replaceAll: { [unowned self] p, template, w in
                guard look(w) == .formulas else { return formulasOnly }
                let n = wb.replaceAll(p, with: template, scope: w.scope)
                return n == 0 ? "No matches" : "Replaced \(n)"
            })
        hooks.orders = ["By Rows", "By Columns"]
        hooks.lookIns = ["Formulas", "Values", "Notes"]
        hooks.findAll = { [unowned self] p, w in
            let lookIn = look(w)
            return wb.findAll(p, scope: w.scope, lookIn: lookIn, byColumns: w.byColumns).map { hit in
                let ws = wb.book.sheets[hit.sheet]
                let c = ws.cells[hit.at]
                let value = lookIn == .notes ? (wb.findText(hit.at, sheet: ws, lookIn: .notes) ?? "")
                    : (wb.findText(hit.at, sheet: ws, lookIn: .values) ?? "")
                let formula = c?.formula.map(Formula.text) ?? ""
                return FindListHit(place: ws.name, cell: "$" + CellAddress.columnName(hit.at.col) + "$" + String(hit.at.row + 1), value: value, formula: formula, go: { [unowned self] in
                    wb.goToHit(hit)
                    _grid?.reveal(wb.active)
                })
            }
        }
        hooks.wholeLabel = "Match entire cell contents"
        hooks.wholeIsEntireCell = true
        hooks.scopes = ["Sheet", "Workbook"]
        hooks.goToLabel = "Go to cell"
        hooks.goToHint = "A cell or range, like B7 or Sheet2!A1:C3"
        hooks.goTo = { [unowned self] text in
            let problem = wb.goTo(text)
            if problem == nil { _grid?.reveal(wb.active) }
            return problem
        }
        return hooks
    }

    // MARK: Notes

    private let _noteFlyout = FlyoutController()

    private func _editNote(at a: CellAddress) {
        guard let context, let grid = _grid else { return }
        _ = grid.commitEdit()
        let menu = _noteFlyout
        let point = grid.globalTopRight(of: a)
        let initial = wb.note(at: a)?.body ?? ""
        menu.showFlyout(in: context, at: point) { [weak self] _ in
            NoteEditor(initial: initial, onSave: { text in
                menu.closeFlyout()
                self?.wb.setNote(text, at: a)
                self?._grid?.focus.requestFocus()
            }, onCancel: {
                menu.closeFlyout()
                self?._grid?.focus.requestFocus()
            })
        }
    }

    // MARK: Validation lists

    private func _showListMenu(at point: Offset, cell: CellAddress, _ choices: [String]) {
        guard let context, !choices.isEmpty else { return }
        let items: [MenuFlyoutItemBase] = choices.map { choice in
            MenuFlyoutItem(text: Text(choice), onPressed: { [weak self] in
                self?.wb.setInputs([(cell, choice)])
                self?._grid?.focus.requestFocus()
            })
        }
        _contextMenu.showFlyout(in: context, at: point) { _ in MenuFlyout(items: items) }
    }

    /// Excel's Paste Options button menu (X-CL-1): the last paste made again another way, in one undo step.
    /// The way it was made is ticked.
    static let pasteOptionChoices: [(String, PasteSpecial)] = [
        ("Paste", PasteSpecial()),
        ("Formulas", PasteSpecial(what: .formulas)),
        ("Formulas & Number Formatting", PasteSpecial(what: .formulasAndNumberFormats)),
        ("Keep Source Column Widths", PasteSpecial(what: .allWithColumnWidths)),
        ("No Borders", PasteSpecial(what: .allExceptBorders)),
        ("Transpose", PasteSpecial(transpose: true)),
        ("Values", PasteSpecial(what: .values)),
        ("Values & Number Formatting", PasteSpecial(what: .valuesAndNumberFormats)),
        ("Values & Source Formatting", PasteSpecial(what: .valuesAndFormats)),
        ("Formatting", PasteSpecial(what: .formats)),
        ("Paste Link", PasteSpecial(link: true)),
    ]

    private func _showPasteOptions(at point: Offset) {
        guard let context, let last = wb.pasteOptions else { return }
        let items: [MenuFlyoutItemBase] = Self.pasteOptionChoices.map { label, how in
            ToggleMenuFlyoutItem(text: Text(label, key: ValueKey("paste-options.\(label)")), isChecked: last.how == how,
                                 onChanged: { [weak self] _ in
                                     self?.wb.repaste(how)
                                     self?._grid?.focus.requestFocus()
                                 })
        }
        _contextMenu.showFlyout(in: context, at: point) { _ in MenuFlyout(items: items) }
    }

    // MARK: Filters

    private func _showFilterMenu(at point: Offset, col: Int) {
        guard let context else { return }
        let menu = _filterMenu
        menu.showFlyout(in: context, at: point) { [weak self] _ in
            guard let self else { return SizedBox(width: 0, height: 0, child: nil) }
            return FilterPanel(controller: self.wb, col: col, onClose: { [weak self] in
                menu.closeFlyout()
                self?._grid?.focus.requestFocus()
            })
        }
    }

    // MARK: The context menu

    /// Excel's right-click menu: the clipboard, then insert/delete for
    /// what was clicked (cells, whole rows, whole columns), then clear,
    /// merge and the size of rows or columns.
    private func _showContextMenu(at point: Offset, _ area: GridMenuArea) {
        guard let grid = _grid else { return }
        let c = wb
        let menu = ContextMenuBuilder()
        func item(_ text: String, enabled: Bool = true, _ action: @escaping () -> Void) { menu.item(text, enabled: enabled, action) }
        func sep() { menu.separator() }
        if case .cells = area {
            let st = c.style(at: c.active)
            menu.miniButton(FluentSystemIcons.textBold, "Bold", on: st.bold) { c.toggleStyle(\.bold) }
            menu.miniButton(FluentSystemIcons.textItalic, "Italic", on: st.italic) { c.toggleStyle(\.italic) }
            menu.miniButton(FluentSystemIcons.textUnderline, "Underline", on: st.underline) { c.toggleStyle(\.underline) }
        }
        // A picture or chart: delete it, or change what kind of chart it is.
        if case .drawing(let i) = area {
            item("Delete") { c.deleteDrawing(i) }
            if c.sheet.drawings.indices.contains(i), case .chart(let sc) = c.sheet.drawings[i].kind {
                sep()
                item("Change to 3-D Chart") { c.setChartVariant(i, .threeD) }
                for t in ChartType.allCases where t != sc.chart.type {
                    item("Change to \(t.name) Chart") { c.setChartType(i, t) }
                }
            }
            guard let context else { return }
            menu.show(_contextMenu, in: context, at: point)
            return
        }
        item("Cut") { grid.copySelection(cut: true) }
        item("Copy") { grid.copySelection() }
        item("Paste") { grid.paste() }
        item("Paste Special…") { [weak self] in self?._openPasteSpecial() }
        sep()
        let sel = c.selection
        switch area {
        case .columns:
            let n = sel.cols
            item(n > 1 ? "Insert \(n) Columns" : "Insert Column") { c.insertAtSelection(.cols) }
            item(n > 1 ? "Delete \(n) Columns" : "Delete Column") { c.deleteAtSelection(.cols) }
        case .rows:
            let n = sel.rows
            item(n > 1 ? "Insert \(n) Rows" : "Insert Row") { c.insertAtSelection(.rows) }
            item(n > 1 ? "Delete \(n) Rows" : "Delete Row") { c.deleteAtSelection(.rows) }
        case .cells:
            item("Insert…") { [weak self] in self?._openCellsDialog(insert: true) }
            item("Delete…") { [weak self] in self?._openCellsDialog(insert: false) }
        case .drawing: break
        }
        // The fill handle's drag, as commands a finger can reach: the selection's first row (or column) copied across it,
        // or, with one row (column) selected, the one before it.
        if case .cells = area {
            item("Fill Down") { c.fillDown() }
            item("Fill Right") { c.fillRight() }
            item("Fill Series…") { [weak self] in self?.setState { self?._seriesOpen = true } }
        }
        item("Clear Contents") { c.clearContents() }
        item("Clear Formats") { c.setStyle { $0 = .plain } }
        item("Format Cells…") { [weak self] in self?._openFormatCells() }
        if case .cells = area {
            sep()
            let has = c.note(at: c.active) != nil
            item(has ? "Edit Note" : "New Note") { [weak self] in self?._editNote(at: c.active) }
            if has { item("Delete Note") { c.deleteNote(at: c.active) } }
            sep()
            let linked = c.link(at: c.active) != nil
            item(linked ? "Edit Hyperlink…" : "Hyperlink…") { [weak self] in self?.setState { self?._linkOpen = true } }
            if linked { item("Remove Hyperlink") { c.removeLink(c.selection) } }
        }
        sep()
        switch area {
        case .columns:
            item("AutoFit Column Width") { grid.autofit(.cols, sel.left) }
            item("Column Width…") { [weak self] in self?._openSizeDialog(.columnWidth) }
            item("Hide") { c.setHidden(.cols, true) }
            item("Unhide") { c.setHidden(.cols, false) }
        case .rows:
            item("AutoFit Row Height") { grid.autofit(.rows, sel.top) }
            item("Row Height…") { [weak self] in self?._openSizeDialog(.rowHeight) }
            item("Hide") { c.setHidden(.rows, true) }
            item("Unhide") { c.setHidden(.rows, false) }
        case .cells:
            if sel.rows > 1 || sel.cols > 1 || c.sheet.merges.contains(where: { $0.intersects(sel) }) {
                if c.sheet.merges.contains(where: { $0.intersects(sel) }) { item("Unmerge Cells") { c.unmerge() } } else { item("Merge & Center") { c.merge(.center) } }
            }
            item("Sort A to Z") { c.sortSelection(ascending: true) }
            item("Sort Z to A") { c.sortSelection(ascending: false) }
        case .drawing: break
        }
        guard let context else { return }
        menu.show(_contextMenu, in: context, at: point)
    }
}
