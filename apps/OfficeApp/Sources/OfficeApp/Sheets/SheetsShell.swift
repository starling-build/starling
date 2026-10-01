// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Sheets window: the title row and ribbon (shared with Writer and
// Slides), the formula bar with its name box, the grid, the sheet tabs,
// and a status bar that sums the selection. Backstage is the shared one,
// with the workbook's own New, Open and Save.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

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
    let session = OfficeSession(kind: .workbook)
    var wb: WorkbookController { session.workbook! }
    private let _gridKey = GlobalKey<State<StatefulWidget>>()
    private var _grid: SheetGridState? { _gridKey.currentState as? SheetGridState }
    private let _formula = TextEditingController()
    private let _nameBox = TextEditingController()
    private let _search = TextEditingController()
    /// The formula bar is being typed in (its text is the user's, not the cell's).
    private var _formulaEditing = false
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
    private var _zoom = 1.0
    private var _windowTitle = ""
    /// The sheet tab being renamed, and its text.
    private var _renaming: Int? = nil
    private let _renameText = TextEditingController()
    private var _lastTabClick: (index: Int, at: Date)? = nil
    private var _findOpen = false
    private var _findReplace = false
    private var _findStatus = ""
    private let _findQuery = TextEditingController()
    private let _findReplacement = TextEditingController()
    private let _contextMenu = FlyoutController()
    private let _filterMenu = FlyoutController()

    private var _w: SheetsShell { widget as! SheetsShell }

    // MARK: Lifecycle

    override func initState() {
        super.initState()
        OfficeFonts.register()
        _recent = OfficeRecent.load()
        _wire()
        wb.addListener({ [weak self] in self?._changed() }, owner: self)
        wb.onCommand = { [weak self] cmd in self?._command(cmd) }
        session.onFind = { [weak self] replace in self?._openFind(replace: replace) }
        if let path = _w.initialPath { _open(path) }
        _syncBars()
    }

    override func dispose() {
        wb.removeListeners(owner: self)
        _formula.dispose()
        _nameBox.dispose()
        _findQuery.dispose()
        _findReplacement.dispose()
        _search.dispose()
        _renameText.dispose()
        super.dispose()
    }

    private func _wire() {
        session.onBackstage = { [weak self] open in self?.setState { self?._backstage = open ? .home : nil } }
        session.onNew = { [weak self] in self?._newWorkbook() }
        session.onNewKind = { [weak self] kind in
            guard let self else { return }
            if kind == .workbook { self._newWorkbook() } else { self._w.onSwitch(kind, nil) }
        }
        session.onOpen = { [weak self] in self?.setState { self?._backstage = .open } }
        session.onSave = { [weak self] in self?._save() }
        session.onSaveAs = { [weak self] in self?.setState { self?._backstage = .saveAs } }
        session.onExport = { [weak self] ext in self?._export(ext) }
        session.onPrint = { [weak self] in self?._print() }
        session.onStatus = { [weak self] m in self?._flash(m) }
        session.onUndo = { [weak self] in self?.wb.undo() }
        session.onRedo = { [weak self] in self?.wb.redo() }
    }

    private func _changed() {
        guard mounted else { return }
        session.dirty = wb.edits != 0
        _syncBars()
        setState {}
    }

    /// The name box shows the active cell (or the selection's size while
    /// dragging); the formula bar shows what was typed into it.
    private func _syncBars() {
        let sel = wb.selection
        let name = sel.isSingle || sel == CellRange(wb.active) ? wb.active.a1
            : (sel.rows == CellAddress.maxRows || sel.cols == CellAddress.maxCols ? sel.a1 : wb.active.a1)
        if _nameBox.text != name { _nameBox.text = name }
        if !_formulaEditing && _grid?.edit == nil { _setFormulaText(wb.input(wb.active)) }
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
        case .copy: grid.copySelection()
        case .cut: grid.copySelection(cut: true)
        case .paste: grid.paste()
        case .startFormula(let text):
            grid.focus.requestFocus()
            grid.beginEdit(replace: text)
        case .zoom(let factor):
            setState { _zoom = factor == 0 ? 1 : max(0.25, min(4, _zoom * factor)) }
        case .toggleGridlines:
            wb.structural { wb.sheet.showGridlines.toggle() }
        case .status(let m):
            _flash(m)
        case .editNote:
            _editNote(at: wb.active)
        }
    }

    // MARK: Files

    private func _newWorkbook() {
        wb.load(Workbook())
        session.path = nil
        session.dirty = false
        setState { _backstage = nil }
    }

    private func _open(_ path: String) {
        let kind = DocumentKind.kind(forPath: path)
        if kind != .workbook {
            _w.onSwitch(kind, path)
            return
        }
        #if os(WASI)
        _flash("Opening files in the browser comes with milestone X5")
        #else
        let ext = path.pathExtension.lowercased()
        guard let data = FileManager.default.contents(atPath: path) else {
            _flash("Could not open \(path.lastPathComponent)")
            return
        }
        if ext == "xlsx" {
            do { wb.load(try Xlsx.read(data)) } catch {
                _flash("Could not open \(path.lastPathComponent): it isn't a workbook Sheets can read")
                return
            }
        } else {
            wb.load(Csv.read(String(decoding: data, as: UTF8.self), name: path.lastPathComponent.deletingPathExtension))
        }
        session.path = path
        session.dirty = false
        _recent = OfficeRecent.remember(path, in: _recent)
        setState { _backstage = nil }
        _flash("Opened \(path.lastPathComponent)")
        #endif
    }

    private func _save() {
        guard let path = session.path, ["xlsx", "csv", "tsv"].contains(path.pathExtension.lowercased()) else {
            setState { _backstage = .saveAs }
            return
        }
        _saveTo(path)
    }

    private func _saveTo(_ chosen: String) {
        #if os(WASI)
        _flash("Saving from the browser comes with milestone X5")
        #else
        let ext = chosen.pathExtension.lowercased()
        let path = ["xlsx", "csv", "tsv"].contains(ext) ? chosen : chosen + ".xlsx"
        let format = path.pathExtension.lowercased()
        _ = _grid?.commitEdit()
        wb.stashViewState()
        do {
            let data: Data
            if format == "xlsx" {
                data = try Xlsx.write(wb.book)
            } else {
                data = Data(Csv.write(wb.sheet, book: wb.book, separator: format == "tsv" ? "\t" : ",").utf8)
            }
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            session.path = path
            wb.markSaved()
            _recent = OfficeRecent.remember(path, in: _recent)
            setState {
                session.dirty = false
                _backstage = nil
            }
            _flash(wb.book.sheets.count > 1 && format != "xlsx"
                   ? "Saved \(path.lastPathComponent) — CSV keeps only the active sheet"
                   : "Saved \(path.lastPathComponent)")
        } catch {
            _flash("Could not save \(path.lastPathComponent): \(error)")
        }
        #endif
    }

    /// PDF or CSV of the active sheet (Excel's own default for both),
    /// beside the workbook or in Documents.
    private func _export(_ ext: String) {
        let base = session.path.map { $0.deletingPathExtension } ?? homeDirectory() + "/Documents/" + session.title.deletingPathExtension
        let target = base + "." + ext
        _ = _grid?.commitEdit()
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
            let ok = await grid.writePdf(to: target, title: self.session.title)
            self._flash(ok ? "Exported \(target.lastPathComponent)" : "Nothing to export on this sheet")
        }
    }

    /// File → Print: the PDF of the active sheet, handed to the host's print dialog.
    private func _print() {
        let path = NSTemporaryDirectory() + "sheets-print-\(ProcessInfo.processInfo.processIdentifier).pdf"
        _ = _grid?.commitEdit()
        setState { _backstage = nil }
        Task { @MainActor [weak self] in
            guard let self, let grid = self._grid else { return }
            guard await grid.writePdf(to: path, title: self.session.title) else {
                self._flash("Nothing to print on this sheet")
                return
            }
            if let print = hostPrintPDF { print(path) } else { self._flash("No print dialog on this host") }
        }
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
                        controller: _nameBox,
                        onSubmitted: { [weak self] text in self?._goTo(text) })),
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
                        controller: _formula,
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
        } else {
            _flash("“\(t)” isn't a cell or a range")
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
            tabs.append(FlatButton(
                child: Padding(padding: EdgeInsets(left: 12, top: 0, right: 12, bottom: 0), child: Column(
                    mainAxisAlignment: .center, crossAxisAlignment: .center, children: [
                        label,
                        Chrome.vgap(2),
                        SizedBox(width: 24, height: 2, child: ColoredBox(color: on ? accent : Color(0x00000000), child: SizedBox(expand: ()))),
                    ])),
                tip: on ? "Double-click to rename" : nil, checked: on, width: nil, height: 28,
                action: { [weak self] in self?._tabClicked(i) }))
        }
        tabs.append(Chrome.icon(FluentSystemIcons.add, "New sheet", fluent) { [weak self] in self?.wb.addSheet() })
        let active = wb.activeSheet
        var sheetMenu: [(String, () -> Void)] = [
            ("Rename Sheet", { [weak self] in self?._startRename(active) }),
            ("Insert Sheet", { [weak self] in self?.wb.addSheet() }),
            ("Delete Sheet", { [weak self] in self?.wb.deleteSheet(active) }),
            ("Hide Sheet", { [weak self] in self?.wb.hideSheet(active) }),
        ]
        // Hidden sheets can be shown again; very hidden ones only by code, as in Excel.
        for (i, ws) in wb.book.sheets.enumerated() where ws.hidden && !ws.veryHidden {
            sheetMenu.append(("Unhide “\(ws.name)”", { [weak self] in self?.wb.unhideSheet(i) }))
        }
        tabs.append(Chrome.menu(nil, Icon(FluentSystemIcons.moreHorizontal, size: Chrome.iconSize,
                                          color: fluent.resources.textFillColorPrimary), fluent, sheetMenu))
        return DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.solidBackgroundFillColorBase,
                border: Border(top: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 8, top: 1, right: 8, bottom: 1), child: Row(
                crossAxisAlignment: .center, children: tabs)))
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
        wb.activeSheet = i
        _grid?.focus.requestFocus()
        _syncBars()
    }

    private func _startRename(_ i: Int) {
        _renameText.text = wb.book.sheets[i].name
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
        if !wb.selection.isSingle {
            let s = wb.selectionStats
            if s.numbers > 0, let avg = s.average {
                right.append(Text("Average: \(NumberFormat.general(avg))", style: caption))
                right.append(Chrome.gap(16))
            }
            if s.count > 0 {
                right.append(Text("Count: \(s.count)", style: caption))
                right.append(Chrome.gap(16))
            }
            if s.numbers > 0 {
                right.append(Text("Sum: \(NumberFormat.general(s.sum))", style: caption))
                right.append(Chrome.gap(16))
            }
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
            child: Padding(padding: EdgeInsets(left: 12, top: 2, right: 8, bottom: 2), child: Row(
                crossAxisAlignment: .center,
                children: left + [Expanded(child: SizedBox(width: 0, height: 0, child: nil))] + right)))
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
                self._findNext(backwards: false)
            }),
            Ribbon(session: session, tab: _tab, collapsed: _ribbonCollapsed,
                   onTab: { [weak self] t in self?.setState { self?._tab = t } },
                   onCollapse: { [weak self] in self?.setState { self?._ribbonCollapsed.toggle() } }),
        ] + (_findOpen ? [FindBar(session: session, query: _findQuery, replacement: _findReplacement,
                                 showReplace: _findReplace, status: _findStatus,
                                 onNext: { [weak self] back in self?._findNext(backwards: back) },
                                 onReplace: { [weak self] in self?._replaceOne() },
                                 onReplaceAll: { [weak self] in self?._replaceAll() },
                                 onClose: { [weak self] in self?._closeFind() })] : []) + [
            _formulaBar(fluent),
            Expanded(child: SheetGrid(
                key: _gridKey, controller: wb, zoom: _zoom,
                onEditText: { [weak self] text in
                    guard let self, !self._formulaEditing else { return }
                    self._setFormulaText(text ?? self.wb.input(self.wb.active))
                    self.setState {}
                },
                onShortcut: { [weak self] letter, chords in self?._shortcut(letter, chords) ?? false },
                onStatus: { [weak self] m in self?._flash(m) },
                onContextMenu: { [weak self] point, area in self?._showContextMenu(at: point, area) },
                onFilterMenu: { [weak self] point, col in self?._showFilterMenu(at: point, col: col) },
                onListMenu: { [weak self] point, cell, choices in self?._showListMenu(at: point, cell: cell, choices) })),
            _sheetTabs(fluent),
            _statusBar(fluent),
        ]
        let window = ColoredBox(color: fluent.scaffoldBackgroundColor,
                                child: Column(crossAxisAlignment: .stretch, children: column))
        guard let page = _backstage else { return window }
        return Stack(children: [
            window,
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Backstage(
                session: session, page: page, recent: _recent,
                onPage: { [weak self] p in self?.setState { self?._backstage = p } },
                onClose: { [weak self] in
                    self?.setState { self?._backstage = nil }
                    self?._grid?.focus.requestFocus()
                },
                onOpenPath: { [weak self] path in self?._open(path) },
                onSavePath: { [weak self] path in self?._saveTo(path) },
                onPicturePath: { _ in })),
        ])
    }

    /// ⌘S, ⌘O, ⌘N, ⌘P — the window's chords, which the grid passes up.
    private func _shortcut(_ letter: Character, _ chords: KeyChordTracker) -> Bool {
        switch letter {
        case "s":
            if chords.shift { setState { _backstage = .saveAs } } else { _save() }
            return true
        case "o": setState { _backstage = .open }; return true
        case "n": _newWorkbook(); return true
        case "p": _print(); return true
        case "f": _openFind(replace: false); return true
        case "h": _openFind(replace: true); return true
        case "l" where chords.shift: wb.toggleAutoFilter(); return true
        // Excel for Mac's Group and Ungroup.
        case "k" where chords.shift: wb.groupRows(true); return true
        case "j" where chords.shift: wb.groupRows(false); return true
        case "\u{1B}":
            if _findOpen { _closeFind(); return true }
            return false
        default: return false
        }
    }

    // MARK: Find

    private func _openFind(replace: Bool) {
        setState {
            _findOpen = true
            _findReplace = replace
            _findStatus = ""
        }
    }

    private func _closeFind() {
        setState { _findOpen = false }
        _grid?.focus.requestFocus()
    }

    private func _findNext(backwards: Bool) {
        let q = _findQuery.text
        guard !q.isEmpty else { return }
        if wb.findNext(q, backwards: backwards) {
            _grid?.reveal(wb.active)
            setState { _findStatus = "" }
        } else {
            setState { _findStatus = "No matches" }
        }
    }

    private func _replaceOne() {
        let q = _findQuery.text
        guard !q.isEmpty else { return }
        if wb.replaceCurrent(q, with: _findReplacement.text) {
            _grid?.reveal(wb.active)
            setState { _findStatus = "" }
        } else {
            setState { _findStatus = "No matches" }
        }
    }

    private func _replaceAll() {
        let n = wb.replaceAll(_findQuery.text, with: _findReplacement.text)
        setState { _findStatus = n == 0 ? "No matches" : "Replaced \(n)" }
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
        var items: [MenuFlyoutItemBase] = []
        func item(_ text: String, enabled: Bool = true, _ action: @escaping () -> Void) {
            items.append(MenuFlyoutItem(text: Text(text), onPressed: enabled ? action : nil))
        }
        func sep() { if !(items.last is MenuFlyoutSeparator), !items.isEmpty { items.append(MenuFlyoutSeparator()) } }
        // A picture or chart: delete it, or change what kind of chart it is.
        if case .drawing(let i) = area {
            item("Delete") { c.deleteDrawing(i) }
            if c.sheet.drawings.indices.contains(i), case .chart(let sc) = c.sheet.drawings[i].kind {
                sep()
                for t in ChartType.allCases where t != sc.chart.type {
                    item("Change to \(t.name) Chart") { c.setChartType(i, t) }
                }
            }
            guard let context else { return }
            _contextMenu.showFlyout(in: context, at: point) { _ in MenuFlyout(items: items) }
            return
        }
        item("Cut") { grid.copySelection(cut: true) }
        item("Copy") { grid.copySelection() }
        item("Paste") { grid.paste() }
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
            item("Insert Rows Above") { c.insertAtSelection(.rows) }
            item("Insert Columns Left") { c.insertAtSelection(.cols) }
            item("Delete Rows") { c.deleteAtSelection(.rows) }
            item("Delete Columns") { c.deleteAtSelection(.cols) }
        case .drawing: break
        }
        item("Clear Contents") { c.clearContents() }
        item("Clear Formats") { c.setStyle { $0 = .plain } }
        if case .cells = area {
            sep()
            let has = c.note(at: c.active) != nil
            item(has ? "Edit Note" : "New Note") { [weak self] in self?._editNote(at: c.active) }
            if has { item("Delete Note") { c.deleteNote(at: c.active) } }
        }
        sep()
        switch area {
        case .columns:
            item("AutoFit Column Width") { grid.autofit(.cols, sel.left) }
        case .rows:
            item("AutoFit Row Height") { grid.autofit(.rows, sel.top) }
        case .cells:
            if sel.rows > 1 || sel.cols > 1 || c.sheet.merges.contains(where: { $0.intersects(sel) }) {
                item(c.sheet.merges.contains(where: { $0.intersects(sel) }) ? "Unmerge Cells" : "Merge & Center") { c.toggleMerge() }
            }
            item("Sort A to Z") { c.sortSelection(ascending: true) }
            item("Sort Z to A") { c.sortSelection(ascending: false) }
        case .drawing: break
        }
        guard let context else { return }
        _contextMenu.showFlyout(in: context, at: point) { _ in MenuFlyout(items: items) }
    }
}
