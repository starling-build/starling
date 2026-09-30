// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The window: title row, ribbon, find bar, ruler, the page area, status
// bar — and Backstage over all of it for File. The shell owns the session
// and rebuilds chrome only when the toolbar summary changes, so typing
// never rebuilds anything but the editor's own painter.

import Flutter
import FlutterSwiftBridge
import Foundation

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

    private var controller: RichDocumentController { session.controller }

    // MARK: Lifecycle

    override func initState() {
        super.initState()
        OfficeFonts.register()
        _recent = _loadRecent()
        _wireSession()
        let env = ProcessInfo.processInfo.environment
        if let pages = env["OFFICE_DEMO_PAGES"].flatMap(Int.init), pages > 0 {
            controller.load(DemoDocument.make(pages: pages))
        } else if let path = (widget as! OfficeShell).initialPath {
            _open(path)
        }
        _savedRevision = controller.revision
        session.summary = session.summarize()
        controller.addListener { [weak self] in
            guard let self else { return }
            let s = self.session.summarize()
            let dirty = self.controller.revision != self._savedRevision
            if s != self.session.summary || dirty != self.session.dirty {
                self.setState {
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
            self.setState { self._backstage = .open }
        }
        session.onSave = { [weak self] in self?._save() }
        session.onSaveAs = { [weak self] in
            guard let self else { return }
            self.setState { self._backstage = .saveAs }
        }
        session.onExport = { [weak self] ext in self?._export(ext) }
        session.onFind = { [weak self] replace in self?._openFind(replace: replace) }
        session.onStatus = { [weak self] msg in self?._flash(msg) }
    }

    // MARK: Documents

    private func _new() {
        controller.load(RichDocument())
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
            let doc = try OfficeFormats.read(path)
            controller.load(doc)
            session.path = path
            _savedRevision = controller.revision
            _remember(path)
            setState {
                session.dirty = false
                session.summary = session.summarize()
                _backstage = nil
            }
            _flash("Opened \((path as NSString).lastPathComponent)")
        } catch {
            _flash("Could not open \((path as NSString).lastPathComponent): \(error)")
            setState { _backstage = nil }
        }
    }

    private func _save() {
        guard let path = session.path else {
            setState { _backstage = .saveAs }
            return
        }
        _saveTo(path)
    }

    private func _saveTo(_ path: String) {
        do {
            try OfficeFormats.write(controller.document, to: path)
            session.path = path
            _savedRevision = controller.revision
            _remember(path)
            setState {
                session.dirty = false
                _backstage = nil
            }
            _flash(OfficeFormats.losesFormatting(path)
                   ? "Saved as plain text — formatting is not kept in .txt"
                   : "Saved \((path as NSString).lastPathComponent)")
        } catch {
            _flash("Could not save: \(error)")
        }
    }

    private func _export(_ ext: String) {
        let base = session.path.map { ($0 as NSString).deletingPathExtension }
            ?? NSHomeDirectory() + "/Documents/" + session.title
        let target = base + "." + ext
        do {
            try OfficeFormats.write(controller.document, to: target)
            _remember(target)
            setState { _backstage = nil }
            _flash("Exported \((target as NSString).lastPathComponent)")
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
        let dir = NSHomeDirectory() + "/.config/starling"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/office-recent.txt"
    }

    private func _loadRecent() -> [String] {
        guard let text = try? String(contentsOfFile: _recentFile, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init).filter { FileManager.default.fileExists(atPath: $0) }
    }

    private func _remember(_ path: String) {
        _recent.removeAll { $0 == path }
        _recent.insert(path, at: 0)
        if _recent.count > 20 { _recent.removeLast(_recent.count - 20) }
        try? _recent.joined(separator: "\n").write(toFile: _recentFile, atomically: true, encoding: .utf8)
    }

    // MARK: Find

    private func _openFind(replace: Bool) {
        setState {
            _findOpen = true
            _findReplace = replace
            _findStatus = ""
        }
        if controller.hasSelection, !controller.selectedText.contains("\n") {
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
           controller.selectedText.compare(q, options: .caseInsensitive) == .orderedSame {
            controller.insertText(_findReplacement.text)
        }
        _findNext(backwards: false)
    }

    private func _replaceAll() {
        let n = controller.replaceAll(_findQuery.text, with: _findReplacement.text)
        setState { _findStatus = n == 0 ? "No matches" : "Replaced \(n)" }
    }

    // MARK: Shortcuts

    private func _shortcut(_ key: KeyData, _ mods: KeyModifiers) -> Bool {
        let named = KeyChordTracker.named(key.logical)
        if named == .escape {
            if _findOpen { setState { _findOpen = false }; return true }
            if _backstage != nil { setState { _backstage = nil }; return true }
            return false
        }
        guard mods.contains(.primary) else { return false }
        guard let letter = KeyChordTracker.letter(key.logical) else {
            // ⌘= / ⌘- / ⌘0 zoom.
            if key.logical == 0x3D || key.logical == 0x2B { session.onZoom?(session.zoom + 0.1); return true }
            if key.logical == 0x2D { session.onZoom?(session.zoom - 0.1); return true }
            if key.logical == 0x30 { session.onZoom?(1.0); return true }
            return false
        }
        switch letter {
        case "s":
            if mods.contains(.shift) { setState { _backstage = .saveAs } } else { _save() }
        case "o": setState { _backstage = .open }
        case "n": _new()
        case "f": _openFind(replace: false)
        case "h": _openFind(replace: true)
        case "g": _findNext(backwards: mods.contains(.shift))
        case "p": setState { _backstage = .print }
        case "e": setState { _backstage = .export }
        default: return false
        }
        return true
    }

    // MARK: Build

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
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
        if session.showRuler && session.viewMode == .printLayout {
            column.append(Ruler(setup: session.pageSetup, zoom: session.zoom,
                                pixelsPerPoint: session.theme.pixelsPerPoint, sidePadding: 24,
                                indentLeft: controller.currentParagraphStyle.indentLeft))
        }
        column.append(Expanded(child: _pageArea(fluent)))
        column.append(StatusBar(session: session, message: _status))

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
                onSavePath: { [weak self] path in self?._saveTo(path) })),
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
            onShortcut: { [weak self] key, mods in self?._shortcut(key, mods) ?? false }
        )
    }
}
