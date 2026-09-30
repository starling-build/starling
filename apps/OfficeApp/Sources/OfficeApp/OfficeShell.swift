// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The window: title row, ribbon, find bar, ruler, the page area, status
// bar — and Backstage over all of it for File. The shell owns the session
// and rebuilds chrome only when the toolbar summary changes, so typing
// never rebuilds anything but the editor's own painter.

import Flutter
import FlutterSwiftBridge
import Foundation
#if os(WASI)
import FlutterWeb
#endif

final class OfficeShell: StatefulWidget {
    let initialPath: String?

    init(initialPath: String?) {
        self.initialPath = initialPath
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        return OfficeShellState()
    }
}

final class OfficeShellState: State<StatefulWidget> {
    let session = OfficeSession()
    private var _tab = RibbonTab.home
    private var _ribbonCollapsed = false
    private var _backstage: BackstagePage? = nil
    private var _findOpen = false
    private var _findReplace = false
    private var _findStatus = ""
    private var _status: String? = nil
    private var _statusGeneration = 0
    private var _savedRevision = 0
    private var _recent: [String] = []
    private let _search = TextEditingController()
    private let _findQuery = TextEditingController()
    private let _findReplacement = TextEditingController()
    private var _headerFooterOpen = false
    private var _linkOpen = false
    private var _colorOpen = false
    private let _colorText = TextEditingController()
    private var _styleOpen: String? = nil
    private let _linkText = TextEditingController()
    private var _linkHover: String? = nil
    private var _autosaveGeneration = 0
    private let _contextMenu = FlyoutController()
    #if canImport(AppKit)
    private let _spelling: RichSpellChecker? = CocoaSpellChecker()
    #else
    private let _spelling: RichSpellChecker? = nil
    #endif
    /// Set when the open document came from a recovery copy: AutoSave then
    /// refreshes only the copy until the user saves for real.
    private var _recovered = false
    private let _headerText = TextEditingController()
    private let _footerText = TextEditingController()

    private var controller: RichDocumentController { session.controller }

    // MARK: Lifecycle

    override func initState() {
        super.initState()
        OfficeFonts.register()
        _recent = _loadRecent()
        _wireSession()
        // `starling.debug('layout')` from the browser's console or a script:
        // the open document's lines and pages, to diff against
        // `OfficeApp --layout` natively.
        hostDebugQuery = { [weak self] kind in
            guard let self, kind == "layout" else { return nil }
            return OfficeLayoutDump.text(self.controller.document, pageSetup: self.session.pageSetup)
        }
        let env = ProcessInfo.processInfo.environment
        if let pages = env["OFFICE_DEMO_PAGES"].flatMap(Int.init), pages > 0 {
            controller.load(DemoDocument.make(pages: pages))
        } else if let path = (widget as! OfficeShell).initialPath {
            _open(path)
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
        _savedRevision = controller.revision
        session.summary = session.summarize()
        controller.addListener { [weak self] in
            guard let self else { return }
            let s = self.session.summarize()
            let dirty = self.controller.revision != self._savedRevision
            if dirty { self._scheduleAutosave() }
            if s != self.session.summary || dirty != self.session.dirty {
                self.setState {
                    // Selecting a picture opens its tab; leaving it returns Home.
                    if s.imageIndex != nil, self.session.summary.imageIndex == nil { self._tab = .pictureFormat }
                    if s.imageIndex == nil, self._tab == .pictureFormat { self._tab = .home }
                    if !s.inCell, self._tab == .tableLayout { self._tab = .home }
                    self.session.summary = s
                    self.session.dirty = dirty
                }
            }
        }
    }

    override func dispose() {
        _search.dispose()
        _findQuery.dispose()
        _findReplacement.dispose()
        _headerText.dispose()
        _linkText.dispose()
        _colorText.dispose()
        _footerText.dispose()
        super.dispose()
    }

    private func _wireSession() {
        session.onZoom = { [weak self] z in
            guard let self else { return }
            self.setState { self.session.zoom = max(0.5, min(3.0, (z * 10).rounded() / 10)) }
        }
        session.onViewMode = { [weak self] m in
            guard let self else { return }
            self.setState {
                self.session.viewMode = m
                self.controller.readOnly = m == .readMode
                if m == .readMode { self._ribbonCollapsed = true }
            }
        }
        session.onToggleRuler = { [weak self] in
            guard let self else { return }
            self.setState { self.session.showRuler.toggle() }
        }
        session.onToggleNavigation = { [weak self] in
            guard let self else { return }
            self.setState { self.session.showNavigation.toggle() }
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
        session.onFormatPainter = { [weak self] in
            guard let self else { return }
            if self.session.paintedStyle != nil {
                self.session.paintedStyle = nil
                self._flash("Format Painter off")
            } else {
                self.session.paintedStyle = self.controller.currentCharStyle
                self.session.paintedStyle?.link = nil
                self._flash("Format Painter: select the text to paint")
            }
            self.setState { self.session.summary = self.session.summarize() }
        }
        session.onPageSetup = { [weak self] p in
            guard let self else { return }
            self.setState { self.session.pageSetup = p }
        }
        session.onBackstage = { [weak self] open in
            guard let self else { return }
            self.setState { self._backstage = open ? .home : nil }
        }
        session.onNew = { [weak self] in self?._new() }
        session.onOpen = { [weak self] in
            guard let self else { return }
            #if os(WASI)
            // The browser's picker, not Backstage's directory list: a tab
            // has no directories, only files the user hands over.
            WebFiles.open(extensions: OfficeFormats.readable) { [weak self] picked in
                guard let self, let picked else { return }
                self._open(picked.name, data: picked.data)
            }
            #else
            self.setState { self._backstage = .open }
            #endif
        }
        session.onSave = { [weak self] in self?._save() }
        session.onSaveAs = { [weak self] in
            guard let self else { return }
            #if os(WASI)
            // The browser names and places a download; "save as" is save.
            self._save()
            #else
            self.setState { self._backstage = .saveAs }
            #endif
        }
        session.onExport = { [weak self] ext in self?._export(ext) }
        session.onFind = { [weak self] replace in self?._openFind(replace: replace) }
        session.onHeaderFooter = { [weak self] in
            guard let self else { return }
            self._headerText.text = self.controller.document.header
            self._footerText.text = self.controller.document.footer
            self.setState { self._headerFooterOpen = true }
        }
        session.onLink = { [weak self] in self?._openLink() }
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
        session.onInsertPicture = { [weak self] in
            guard let self else { return }
            self.setState { self._backstage = .insertPicture }
        }
        session.onStatus = { [weak self] msg in self?._flash(msg) }
        session.onToggleAutoSave = { [weak self] in
            guard let self else { return }
            self.setState { self.session.autoSave.toggle() }
            self._flash(self.session.autoSave ? "AutoSave on" : "AutoSave off — a recovery copy is still kept")
            self._scheduleAutosave()
        }
        session.onPrint = { [weak self] in self?._print() }
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
    private func _print() {
        #if os(WASI)
        _flash("Printing is not available in the browser yet")
        #else
        let path = NSTemporaryDirectory() + "office-print-\(ProcessInfo.processInfo.processIdentifier).pdf"
        guard PdfExport.write(controller.document, pageSetup: session.pageSetup, theme: session.theme,
                              to: path, title: session.title) else {
            _flash("Could not render the document for printing")
            return
        }
        setState { _backstage = nil }
        if let print = hostPrintPDF { print(path) } else { _flash("No print dialog on this host") }
        #endif
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
        let dir = NSHomeDirectory() + "/.config/starling/office-recovery"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/untitled.docx~"
        #endif
    }

    /// Two seconds after the last edit: AutoSave writes the file itself
    /// when it is on and the document has one; either way the recovery
    /// copy is refreshed.
    private func _scheduleAutosave() {
        #if os(WASI)
        // The browser has no files of ours to write: the document lives in
        // the page until the user downloads it. No recovery copy either.
        return
        #else
        _autosaveGeneration += 1
        let gen = _autosaveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [weak self] in
            guard let self, self._autosaveGeneration == gen, self.session.dirty else { return }
            // AutoSave writes the file itself — never a recovered document,
            // whose on-disk file the user has not yet chosen to replace.
            if self.session.autoSave, !self._recovered, let path = self.session.path {
                do {
                    try OfficeFormats.write(self.controller.document, to: path, pageSetup: self.session.pageSetup)
                    self._savedRevision = self.controller.revision
                    try? FileManager.default.removeItem(atPath: self._recoveryPath(for: path))
                    self.setState { self.session.dirty = false }
                    return
                } catch {
                    self._flash("AutoSave could not write: \(error)")
                    // Fall through: at least the recovery copy.
                }
            }
            let recovery = self._recoveryPath(for: self.session.path)
            if let data = try? DocxFormat.write(self.controller.document, pageSetup: self.session.pageSetup) {
                try? data.write(to: URL(fileURLWithPath: recovery), options: .atomic)
            }
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
        controller.load(blank)
        session.path = nil
        _savedRevision = controller.revision
        setState {
            session.dirty = false
            session.summary = session.summarize()
            _backstage = nil
        }
    }

    private func _open(_ path: String) {
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
                if let setup = opened.pageSetup { session.pageSetup = setup }
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
    private func _open(_ name: String, data: Data) {
        do {
            try _open(name, opened: OfficeFormats.read(data, named: name))
        } catch {
            _flash("Could not open \(name): \(error)")
        }
    }

    private func _open(_ path: String, opened: OpenedDocument) throws {
        controller.load(opened.document)
        session.path = path
        _savedRevision = controller.revision
        _remember(path)
        setState {
            if let setup = opened.pageSetup { session.pageSetup = setup }
            session.dirty = false
            session.summary = session.summarize()
            _backstage = nil
        }
        _flash("Opened \(path.lastPathComponent)")
    }

    private func _save() {
        #if os(WASI)
        // A download, named after the document; the browser decides where
        // it goes, and asks the user if it is set to.
        let name = session.path ?? session.title + ".docx"
        do {
            let data = try OfficeFormats.encode(controller.document, as: name.pathExtension,
                                                pageSetup: session.pageSetup)
            WebFiles.download(data, as: name)
            session.path = name
            _savedRevision = controller.revision
            setState {
                session.dirty = false
                _backstage = nil
            }
            _flash("Saved \(name)")
        } catch {
            _flash("Could not save: \(error)")
        }
        #else
        guard let path = session.path else {
            setState { _backstage = .saveAs }
            return
        }
        _saveTo(path)
        #endif
    }

    private func _saveTo(_ path: String) {
        do {
            try OfficeFormats.write(controller.document, to: path, pageSetup: session.pageSetup)
            // The recovery copies this document may have left: under its
            // new name, its old name, and the untitled slot if it had no name.
            let fm = FileManager.default
            try? fm.removeItem(atPath: _recoveryPath(for: path))
            if let old = session.path, old != path { try? fm.removeItem(atPath: _recoveryPath(for: old)) }
            if session.path == nil { try? fm.removeItem(atPath: _recoveryPath(for: nil)) }
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
            _flash("Could not save: \(error)")
        }
    }

    private func _export(_ ext: String) {
        let base = session.path.map { $0.deletingPathExtension }
            ?? homeDirectory() + "/Documents/" + session.title
        let target = base + "." + ext
        #if os(WASI)
        do {
            guard ext != "pdf" else { _flash("PDF export is not available in the browser yet"); return }
            let data = try OfficeFormats.encode(controller.document, as: ext, pageSetup: session.pageSetup)
            WebFiles.download(data, as: target.lastPathComponent)
            setState { _backstage = nil }
            _flash("Exported \(target.lastPathComponent)")
        } catch {
            _flash("Could not export: \(error)")
        }
        return
        #endif
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

    private func _flash(_ message: String) {
        _statusGeneration += 1
        let gen = _statusGeneration
        setState { _status = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(4)) { [weak self] in
            guard let self, self._statusGeneration == gen else { return }
            self.setState { self._status = nil }
        }
    }

    // Recent files live beside the user's other Starling state.
    private var _recentFile: String {
        let dir = homeDirectory() + "/.config/starling"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/office-recent.txt"
    }

    private func _loadRecent() -> [String] {
        #if os(WASI)
        // No files, so no recent files. (FileManager.createDirectory with
        // intermediates recurses forever on WASI, so this cannot even try.)
        return []
        #endif
        guard let text = try? String(contentsOfFile: _recentFile, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init).filter { FileManager.default.fileExists(atPath: $0) }
    }

    private func _remember(_ path: String) {
        _recent.removeAll { $0 == path }
        _recent.insert(path, at: 0)
        if _recent.count > 20 { _recent.removeLast(_recent.count - 20) }
        #if !os(WASI)
        try? _recent.joined(separator: "\n").write(toFile: _recentFile, atomically: true, encoding: .utf8)
        #endif
    }

    // MARK: Pictures

    /// Decode for the intrinsic size (pixels read as 96/in), then insert.
    private func _insertPicture(_ path: String) {
        setState { _backstage = nil }
        guard let data = FileManager.default.contents(atPath: path) else {
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
    }

    private func _findNext(backwards: Bool) {
        let q = _findQuery.text
        guard !q.isEmpty else { return }
        if let sel = controller.find(q, backwards: backwards) {
            controller.selection = sel
            setState { _findStatus = "" }
        } else {
            setState { _findStatus = "No matches" }
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

    private func _paste(plain: Bool) {
        Clipboard.getData(plain ? Clipboard.kTextPlain : Clipboard.kAll) { [weak self] data in
            guard let self, let data, !data.isEmpty else { return }
            DispatchQueue.main.async {
                if plain, let text = data.text {
                    self.controller.insertText(text.replacingAll("\r\n", with: "\n"))
                } else {
                    self.controller.paste(data: data)
                }
            }
        }
    }

    /// Word's right-click menu: what the caret is on, then the clipboard,
    /// then formatting, then the table or picture it sits in.
    private func _showContextMenu(at point: Offset) {
        let c = controller
        var items: [MenuFlyoutItemBase] = []
        func item(_ text: String, enabled: Bool = true, _ action: @escaping () -> Void) {
            items.append(MenuFlyoutItem(text: Text(text), onPressed: enabled ? action : nil))
        }
        func sep() { if !(items.last is MenuFlyoutSeparator), !items.isEmpty { items.append(MenuFlyoutSeparator()) } }
        // A misspelled word under the click: its corrections first, as Word.
        if let checker = _spelling, session.checkSpelling, !c.hasSelection {
            let pos = c.selection.focus
            let text = c.document.paragraphs[pos.paragraph].text
            if let r = checker.misspelledRanges(in: text).first(where: { $0.lowerBound <= pos.offset && pos.offset <= $0.upperBound }) {
                let word = _utf16Slice(text, r)
                let guesses = checker.suggestions(for: word).prefix(5)
                if guesses.isEmpty {
                    items.append(MenuFlyoutItem(text: Text("(No Spelling Suggestions)"), onPressed: nil))
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
            item("Open Link") { hostOpenURL?(link) }
            item("Edit Link…") { [weak self] in self?._openLink() }
            item("Remove Link") { c.setLink(nil) }
            sep()
        }
        let has = c.hasSelection
        item("Cut", enabled: has) { if let d = c.cutSelectionData() { Clipboard.setData(d) } }
        item("Copy", enabled: has) { if let d = c.copySelectionData() { Clipboard.setData(d) } }
        item("Paste") { [weak self] in self?._paste(plain: false) }
        item("Paste as Plain Text") { [weak self] in self?._paste(plain: true) }
        sep()
        item("Bold") { c.toggleBold() }
        item("Italic") { c.toggleItalic() }
        item("Underline") { c.toggleUnderline() }
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
        _contextMenu.showFlyout(in: context, at: point) { _ in MenuFlyout(items: items) }
    }

    // MARK: Links

    private func _openLink() {
        _linkText.text = controller.currentLink ?? ""
        setState { _linkOpen = true }
    }

    private func _applyLink() {
        var url = _linkText.text.trimmingWhitespace()
        guard !url.isEmpty else { setState { _linkOpen = false }; return }
        // A bare host becomes https, a bare address mailto.
        if !url.containsSubstring("://") && !url.hasPrefix("mailto:") && !url.hasPrefix("#") {
            url = url.containsSubstring("@") && !url.containsSubstring("/") ? "mailto:" + url : "https://" + url
        }
        controller.setLink(url)
        setState { _linkOpen = false }
        _flash("Linked to \(url)")
    }

    // MARK: Shortcuts

    private func _shortcut(_ key: KeyData, _ mods: KeyModifiers) -> Bool {
        let named = KeyChordTracker.named(key.logical)
        if named == .escape {
            if _styleOpen != nil { setState { _styleOpen = nil }; return true }
            if _linkOpen { setState { _linkOpen = false }; return true }
            if _colorOpen { setState { _colorOpen = false }; return true }
            if _headerFooterOpen { setState { _headerFooterOpen = false }; return true }
            if _findOpen { setState { _findOpen = false }; return true }
            if _backstage != nil { setState { _backstage = nil }; return true }
            return false
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
            if key.logical == 0x2D { session.onZoom?(session.zoom - 0.1); return true }
            if key.logical == 0x30 { session.onZoom?(1.0); return true }
            if key.logical == 0x5D { c.stepFontSize(1, base: session.effectiveFontSize); return true }
            if key.logical == 0x5B { c.stepFontSize(-1, base: session.effectiveFontSize); return true }
            return false
        }
        if mods.contains(.alt) { return false }
        switch letter {
        case "s":
            if mods.contains(.shift) { setState { _backstage = .saveAs } } else { _save() }
        case "o": session.onOpen?()
        case "n": _new()
        case "f": _openFind(replace: false)
        case "h": _openFind(replace: true)
        case "g": _findNext(backwards: mods.contains(.shift))
        case "p": setState { _backstage = .print }
        case "k": _openLink()
        // Word's alignment keys; Export lives in Backstage.
        case "e": c.setAlignment(.center)
        case "l" where mods.contains(.shift): c.toggleList(.bullet)   // ⌘⇧L: bullets, as in Word
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
            column.append(Ribbon(session: session, tab: _tab, collapsed: _ribbonCollapsed,
                                 onTab: { [weak self] t in self?.setState { self?._tab = t } },
                                 onCollapse: { [weak self] in self?.setState { self?._ribbonCollapsed.toggle() } }))
        }
        if _findOpen {
            column.append(FindBar(session: session, query: _findQuery, replacement: _findReplacement,
                                  showReplace: _findReplace, status: _findStatus,
                                  onNext: { [weak self] back in self?._findNext(backwards: back) },
                                  onReplace: { [weak self] in self?._replaceOne() },
                                  onReplaceAll: { [weak self] in self?._replaceAll() },
                                  onClose: { [weak self] in self?.setState { self?._findOpen = false } }))
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
        if _linkOpen {
            column.append(LinkBar(session: session, address: _linkText, hasLink: controller.currentLink != nil,
                                  onApply: { [weak self] in self?._applyLink() },
                                  onRemove: { [weak self] in
                                      guard let self else { return }
                                      self.controller.setLink(nil)
                                      self.setState { self._linkOpen = false }
                                  },
                                  onClose: { [weak self] in self?.setState { self?._linkOpen = false } }))
        }
        if _headerFooterOpen {
            column.append(HeaderFooterBar(session: session, header: _headerText, footer: _footerText,
                                          onApply: { [weak self] in
                                              guard let self else { return }
                                              self.controller.setHeaderFooter(header: self._headerText.text,
                                                                              footer: self._footerText.text)
                                              self.setState { self._headerFooterOpen = false }
                                          },
                                          onClose: { [weak self] in self?.setState { self?._headerFooterOpen = false } }))
        }
        // The document column: ruler over the pages, beside the navigation
        // pane when it is open.
        var pages: [Widget] = []
        if session.showRuler && session.viewMode == .printLayout {
            pages.append(Ruler(setup: session.pageSetup, zoom: session.zoom,
                               pixelsPerPoint: session.theme.pixelsPerPoint, sidePadding: 24,
                               indentLeft: controller.currentParagraphStyle.indentLeft))
        }
        pages.append(Expanded(child: _pageArea(fluent)))
        var area: [Widget] = []
        if session.showNavigation {
            area.append(NavigationPane(session: session, onClose: { [session] in session.onToggleNavigation?() }))
        }
        area.append(Expanded(child: Column(crossAxisAlignment: .stretch, children: pages)))
        column.append(Expanded(child: Row(crossAxisAlignment: .stretch, children: area)))
        column.append(StatusBar(session: session, message: _status ?? _linkHover.map { "⌘-click to open \($0)" }))

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
                onSavePath: { [weak self] path in self?._saveTo(path) },
                onPicturePath: { [weak self] path in self?._insertPicture(path) })),
        ])
    }

    private func _pageArea(_ fluent: FluentThemeData) -> Widget {
        let dark = fluent.brightness == .dark
        let backdrop = dark ? Color(0xFF202020) : Color(0xFFE6E6E6)
        let page = dark ? Color(0xFF2B2B2B) : Color(0xFFFFFFFF)
        let theme = session.theme
        theme.textColor = dark ? Color(0xFFF0F0F0) : Color(0xFF1B1B1B)
        theme.caretColor = theme.textColor
        let paged = session.viewMode == .printLayout
        let readMargin = session.viewMode == .readMode ? 120.0 : 24.0
        return RichEditable(
            controller: controller, theme: theme,
            padding: EdgeInsets(left: readMargin, top: 24, right: readMargin, bottom: 24),
            backgroundColor: paged ? backdrop : page, zoom: session.zoom,
            pageSetup: paged ? session.pageSetup : nil, pageColor: page,
            onPageInfo: { [weak self] p, n in
                guard let self, self.session.pageInfo != (p, n) else { return }
                self.setState { self.session.pageInfo = (p, n) }
            },
            onShortcut: { [weak self] key, mods in self?._shortcut(key, mods) ?? false },
            onLinkHover: { [weak self] link in
                guard let self, self._linkHover != link else { return }
                self.setState { self._linkHover = link }
            },
            // Format Painter applies when a selection gesture ends, as Word does.
            onSelectionGestureEnd: { [weak self] in
                guard let self, let painted = self.session.paintedStyle else { return }
                self.session.paintedStyle = nil
                self.controller.applyCharStyle { style in
                    let link = style.link
                    style = painted
                    style.link = link   // formatting travels, the hyperlink stays
                }
                self._flash("Painted")
                self.setState { self.session.summary = self.session.summarize() }
            },
            onContextMenu: { [weak self] point in self?._showContextMenu(at: point) },
            spellChecker: session.checkSpelling ? _spelling : nil
        )
    }
}

/// `text` between two UTF-16 offsets (the spell checker's ranges), as a
/// String — `NSString.substring(with:)` without the legacy Foundation
/// layer, which the browser build does not link.
func _utf16Slice(_ text: String, _ r: Range<Int>) -> String {
    let u = text.utf16
    guard r.lowerBound >= 0, r.upperBound <= u.count else { return "" }
    let a = u.index(u.startIndex, offsetBy: r.lowerBound)
    let b = u.index(u.startIndex, offsetBy: r.upperBound)
    return String(u[a ..< b]) ?? ""
}
