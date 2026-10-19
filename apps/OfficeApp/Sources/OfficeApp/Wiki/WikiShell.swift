// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The wiki client (docs/plans/wiki.md W1): a space's page tree on the
// left, one page in the Writer on the right — read-only until Edit takes
// the lock, saved as a new version, drawn in the flow layout. The same
// code runs in a tab (same-origin API) and natively (`--wiki <url>`).

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation
#if os(WASI)
import FlutterWeb
#endif

/// The app rooted on the wiki: `base` is the server ("" in a tab), `route`
/// the page to open (`/s/<space>/p/<id>/<slug>`, `/s/<space>`, or `/`).
final class WikiRoot: StatelessWidget {
    let base: String
    let route: String
    init(base: String, route: String) {
        self.base = base
        self.route = route
        super.init()
    }
    override func build(_ context: any BuildContext) -> Widget {
        FluentApp(theme: WikiAppearance.theme, themeMode: .light,
                  home: ButtonTheme(data: WikiAppearance.buttons, child: WikiShell(session: WikiSession(base: base), route: route)), title: "Starling Office — Wiki")
    }
}

final class WikiShell: StatefulWidget {
    let session: WikiSession
    let route: String
    init(session: WikiSession, route: String) {
        self.session = session
        self.route = route
        super.init()
    }
    override func createState() -> State<StatefulWidget> { WikiShellState() }
}

final class WikiShellState: State<StatefulWidget> {
    var session: WikiSession { (widget as! WikiShell).session }

    // Who and where.
    private var _user: WikiUser?
    private var _needLogin = false
    private var _loginError: String?
    private let _loginField = TextEditingController()
    private let _passwordField = TextEditingController()

    private var _spaces: [WikiSpace] = []
    private var _space: WikiSpace?
    private var _tree: [WikiPageNode] = []

    // The page on screen.
    private var _page: WikiPage?
    private let _controller = RichDocumentController()
    private let _editorFocus = FocusNode()
    private let _theme: RichTextTheme = OfficeSession(kind: .document).theme
    private var _editing = false
    /// The whole Writer, on the page, while editing (HostedDocument).
    private var _writer: OfficeShell?
    private var _lock: WikiLock?
    private var _heartbeat = 0          // generation token for the lock renewal
    private var _dirty = false
    private let _titleField = TextEditingController()
    private var _otherLock: WikiLock?   // someone else's, shown in read mode

    // Small chrome state.
    private var _status: String?
    private var _newTitleOpen = false
    private let _newTitleField = TextEditingController()
    private var _loading = false
    private var _previousMetrics: (() -> Void)?
    private var _compact = false
    private var _navigationOpen = false
    private var _historyOpen = false
    private var _versions: [WikiVersion] = []
    private var _confirmDelete = false
    private let _searchField = TextEditingController()
    private var _hits: [WikiHit]? = nil      // nil: not searching; []: nothing found
    private var _searchGeneration = 0

    override func initState() {
        super.initState()
        _previousMetrics = PlatformDispatcher.instance.onMetricsChanged
        PlatformDispatcher.instance.onMetricsChanged = { [weak self] in
            self?._previousMetrics?()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.mounted else { return }
                self.setState {}
            }
        }
        _controller.readOnly = true
        _controller.addListener { [weak self] in
            guard let self, self._editing, !self._dirty else { return }
            self.setState { self._dirty = true }
        }
        #if os(WASI)
        WebHistory.onRouteChanged = { [weak self] route in self?._open(route: route, push: false) }
        #endif
        session.me { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let u): self._user = u; self._open(route: (self.widget as! WikiShell).route, push: false)
            case .failure(let e): self.setState { self._needLogin = true; self._loginError = e.status == 401 ? nil : "\(e)" }
            }
        }
    }

    override func dispose() {
        PlatformDispatcher.instance.onMetricsChanged = _previousMetrics
        super.dispose()
    }

    // MARK: Navigation

    /// Open what the route names: a page, a space's home, or the first space.
    private func _open(route: String, push: Bool) {
        let parts = route.split(separator: "?")[0].split(separator: "#")[0].split(separator: "/").map(String.init)
        // ["s", KEY, "p", ID, slug…]
        if parts.count >= 2, parts[0] == "s" {
            let key = parts[1]
            let pageID = parts.count >= 4 && parts[2] == "p" ? parts[3] : nil
            _loadSpace(key) { [weak self] space in
                guard let self else { return }
                if let pageID { self._loadPage(pageID, push: push) }
                else if let home = space.homePage { self._loadPage(home, push: push) }
            }
            return
        }
        session.spaces { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let spaces):
                self.setState { self._spaces = spaces }
                if let first = spaces.first { self._open(route: "/s/\(first.key)", push: push) }
                else { self.setState { self._status = "No spaces yet. Create one with wiki-server create-space." } }
            case .failure(let e): self._report(e)
            }
        }
    }

    private func _loadSpace(_ key: String, _ then: @escaping (WikiSpace) -> Void) {
        if let s = _space, s.key == key { _refreshTree(); then(s); return }
        session.space(key) { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let space):
                self.setState { self._space = space }
                self._refreshTree()
                then(space)
            case .failure(let e): self._report(e)
            }
        }
        if _spaces.isEmpty { session.spaces { [weak self] r in if case .success(let s) = r { self?.setState { self?._spaces = s } } } }
    }

    private func _refreshTree() {
        guard let space = _space else { return }
        session.tree(space.key) { [weak self] r in
            if case .success(let nodes) = r { self?.setState { self?._tree = nodes } }
        }
    }

    private func _loadPage(_ id: String, version: Int? = nil, push: Bool) {
        if _editing { _cancelEdit(reload: false) }
        setState { _loading = true }
        session.page(id, version: version) { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let page):
                guard let doc = WikiSession.decodeBody(page.body) else { self.setState { self._loading = false; self._status = "This page's content cannot be read by this build." }; return }
                self.setState {
                    self._page = page
                    if self._compact { self._navigationOpen = false; self._historyOpen = false }
                    self._loading = false
                    self._status = nil
                    self._otherLock = nil
                    self._confirmDelete = false
                    self._titleField.text = page.title
                }
                if self._historyOpen { self._loadVersions() }
                self._controller.load(doc)
                self._controller.readOnly = true
                #if os(WASI)
                if push { WebHistory.push(self.session.pageRoute(space: page.space, id: page.id, slug: page.slug)) }
                #endif
                self.session.currentLock(page.id) { [weak self] r in
                    if case .success(let lock) = r, lock.userID != self?._user?.id { self?.setState { self?._otherLock = lock } }
                }
            case .failure(let e): self.setState { self._loading = false }; self._report(e)
            }
        }
    }

    private func _report(_ e: WikiError) {
        if e.status == 401 { setState { _needLogin = true; _user = nil } ; return }
        setState { _status = "\(e)" }
    }

    // MARK: Editing

    private func _beginEdit() {
        guard let page = _page else { return }
        session.lock(page.id, token: nil) { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let lock):
                // Editing is the whole Writer on the page's document: ribbon,
                // styles, find, export — not a toolbar over the reader.
                var doc = self._controller.document
                if page.body.trimmingWhitespace() == "{}" { doc.styles = OfficeStyles.sheet }
                let writer = OfficeShell(initialPath: nil, hosted: HostedDocument(
                    title: page.title, document: doc, ownerName: "wiki",
                    save: { [weak self] doc, done in self?._saveHosted(doc, done) },
                    close: { [weak self] in self?._cancelEdit(reload: true) }))
                self.setState { self._lock = lock; self._editing = true; self._dirty = false; self._otherLock = nil; self._writer = writer }
                self._scheduleHeartbeat()
            case .failure(let e): self._report(e)
            }
        }
    }

    private func _scheduleHeartbeat() {
        _heartbeat += 1
        let gen = _heartbeat
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            guard let self, self._editing, gen == self._heartbeat, let page = self._page, let lock = self._lock else { return }
            self.session.lock(page.id, token: lock.token) { [weak self] r in
                guard let self else { return }
                if case .success(let renewed) = r { self._lock = renewed; self._scheduleHeartbeat() }
                else { self.setState { self._status = "The edit lock was lost; save soon or copy your text." } }
            }
        }
    }

    /// Writer's Save: the document becomes the page's next version.
    private func _saveHosted(_ doc: RichDocument, _ done: @escaping (String?) -> Void) {
        guard let page = _page, _editing else { done("Not editing a page."); return }
        guard let body = WikiSession.encodeBody(doc) else { done("Could not encode the page."); return }
        session.save(page.id, title: page.title, body: body, plainText: WikiSession.plainText(doc),
                     links: WikiSession.linkedPages(doc), base: page.version, lockToken: _lock?.token) { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let saved):
                self._page = saved
                self._controller.load(doc)
                self._refreshTree()
                done(nil)
            case .failure(let e):
                if e.status == 401 { self._report(e) }
                done(e.status == 409 ? "Someone saved this page while you edited. Export your changes, then go back and Edit again."
                                     : "Could not save: \(e)")
            }
        }
    }

    private func _cancelEdit(reload: Bool) {
        _heartbeat += 1
        if let page = _page, let lock = _lock { session.unlock(page.id, token: lock.token) {} }
        setState { _editing = false; _lock = nil; _dirty = false; _writer = nil }
        _controller.readOnly = true
        if reload, let page = _page { _loadPage(page.id, push: false) }
    }

    private func _createPage(_ title: String) {
        guard let space = _space, !title.isEmpty else { return }
        let parent = _page?.id ?? space.homePage
        session.createPage(space: space.key, title: title, parent: parent) { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let page):
                self.setState { self._newTitleOpen = false; self._newTitleField.text = "" }
                self._refreshTree()
                self._loadPage(page.id, push: true)
            case .failure(let e): self._report(e)
            }
        }
    }

    private func _importDocx() {
        guard let space = _space else { return }
        let parent = _page?.id ?? space.homePage
        #if os(WASI)
        WebFiles.open(extensions: ["docx", "rtf", "md"]) { [weak self] picked in
            guard let self, let picked else { return }
            self.setState { self._status = "Importing \(picked.name)…" }
            self.session.importFile(space: space.key, name: picked.name, parent: parent, data: picked.data) { [weak self] r in
                guard let self else { return }
                switch r {
                case .success(let page): self._refreshTree(); self._loadPage(page.id, push: true)
                case .failure(let e): self._report(e)
                }
            }
        }
        #else
        setState { _status = "Import a file: wiki-server import --space \(space.key) <file.docx>" }
        _ = parent
        #endif
    }

    private func _exportDocx() {
        guard let page = _page else { return }
        session.exportDocx(page.id) { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let data):
                #if os(WASI)
                WebFiles.download(data, as: "\(page.slug).docx")
                #else
                let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(page.slug).docx").path
                try? data.write(to: URL(fileURLWithPath: path))
                self.setState { self._status = "Exported to \(path)" }
                #endif
            case .failure(let e): self._report(e)
            }
        }
    }

    private func _search(_ query: String) {
        let q = query.trimmingWhitespace(newlines: false)
        _searchGeneration += 1
        let gen = _searchGeneration
        guard !q.isEmpty else { setState { _hits = nil }; return }
        session.search(q, space: nil) { [weak self] r in
            guard let self, gen == self._searchGeneration else { return }
            if case .success(let hits) = r { self.setState { self._hits = hits } } else { self.setState { self._hits = [] } }
        }
    }

    private func _loadVersions() {
        guard let page = _page else { return }
        session.versions(page.id) { [weak self] r in
            if case .success(let v) = r { self?.setState { self?._versions = v } }
        }
    }

    /// An old version becomes the newest: its content saved again on top
    /// of the tip, so nothing is lost and the history shows the restore.
    private func _restore() {
        guard let page = _page, page.version < page.tip else { return }
        setState { _loading = true }
        session.save(page.id, title: page.title, body: page.body, plainText: page.plainText, links: page.links,
                     base: page.tip, lockToken: nil) { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let saved):
                self.setState { self._loading = false; self._status = "Restored as version \(saved.version)." }
                self._loadPage(saved.id, push: false)
            case .failure(let e): self.setState { self._loading = false }; self._report(e)
            }
        }
    }

    private func _deletePage() {
        guard let page = _page, let space = _space else { return }
        session.deletePage(page.id) { [weak self] r in
            guard let self else { return }
            switch r {
            case .success:
                self.setState { self._confirmDelete = false; self._status = "Deleted \(page.title)." }
                self._refreshTree()
                self._open(route: "/s/\(space.key)", push: true)
            case .failure(let e): self._report(e)
            }
        }
    }

    private func _login() {
        let login = _loginField.text.trimmingWhitespace(newlines: false)
        let password = _passwordField.text
        guard !login.isEmpty else { return }
        session.login(login, password: password) { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let u):
                self.setState { self._user = u; self._needLogin = false; self._loginError = nil; self._passwordField.text = "" }
                self._open(route: (self.widget as! WikiShell).route, push: false)
            case .failure(let e): self.setState { self._loginError = e.status == 401 ? "Wrong login or password." : "\(e)" }
            }
        }
    }

    private func _shortcut(_ key: KeyData, _ mods: KeyModifiers) -> Bool {
        guard mods.contains(.primary), let letter = KeyChordTracker.letter(key.logical) else { return false }
        switch letter {
        case "e": if !_editing { _beginEdit() }; return true
        default: return false
        }
    }

    // MARK: Build

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        if let view = PlatformDispatcher.instance.implicitView {
            _compact = view.physicalSize.width / view.devicePixelRatio < 900
        }
        if self._needLogin { return self._loginView(fluent) }
        // Editing: the whole Writer, nothing of the wiki's chrome around it.
        if self._editing, let writer = self._writer { return writer }
        var column: [Widget] = [self._header(fluent)]
        column.append(Expanded(child: self._editor(fluent)))
        column.append(self._statusBar(fluent))
        let main = Padding(padding: EdgeInsets(all: self._compact ? 12 : 24), child: DecoratedBox(
            decoration: BoxDecoration(color: WikiAppearance.white, border: Border.all(color: WikiAppearance.line),
                                      borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: .stretch, children: column)))
        let content: Widget
        if self._compact && self._navigationOpen { content = self._sidebar(fluent) }
        else if self._compact && self._historyOpen && self._page != nil { content = self._historyPane(fluent) }
        else {
            var row: [Widget] = []
            if !self._compact { row.append(self._sidebar(fluent)) }
            row.append(Expanded(child: main))
            if !self._compact && self._historyOpen && self._page != nil { row.append(self._historyPane(fluent)) }
            content = Row(crossAxisAlignment: .stretch, children: row)
        }
        return ColoredBox(color: WikiAppearance.paper, child: Column(crossAxisAlignment: .stretch, children: [
            self._brandHeader(), Expanded(child: content),
        ]))
    }

    private func _brandHeader() -> Widget {
        var items: [Widget] = [
            SizedBox(width: 30, height: 30, child: DecoratedBox(
                decoration: BoxDecoration(color: WikiAppearance.blue, borderRadius: BorderRadius.circular(7)),
                child: Center(child: SizedBox(width: 13, height: 18, child: ColoredBox(color: WikiAppearance.white))))),
            Chrome.gap(10), Text("Starling", style: WikiAppearance.text(23, bold: true)), Chrome.gap(8),
            Text("Office", style: WikiAppearance.text(20, color: WikiAppearance.muted)),
            Expanded(child: SizedBox(width: 0, height: 0, child: nil)),
        ]
        if !_needLogin && _compact {
            items.append(Button(onPressed: { [weak self] in self?.setState { self?._navigationOpen.toggle(); self?._historyOpen = false } },
                                child: Text(_navigationOpen ? "Close" : "Pages")))
        } else {
            items.append(Text(_user?.name ?? "TEAM KNOWLEDGE", style: WikiAppearance.text(13, bold: true, color: WikiAppearance.muted)))
        }
        return SizedBox(height: 72, child: ColoredBox(color: WikiAppearance.white, child:
            Padding(padding: EdgeInsets(horizontal: _compact ? 20 : 32), child: Row(children: items))))
    }

    private func _loginView(_ fluent: FluentThemeData) -> Widget {
        var rows: [Widget] = [
            Text("YOUR TEAM / ONE PLACE", style: WikiAppearance.text(12, bold: true, color: WikiAppearance.blue)),
            Chrome.vgap(16), Text("Your team's knowledge.", style: WikiAppearance.text(32, bold: true)),
            Chrome.vgap(10), Text("Sign in to read, write, and share pages with your team.", style: WikiAppearance.text(17, color: WikiAppearance.muted)),
            Chrome.vgap(28), WikiAppearance.field(_loginField, placeholder: "Login", onSubmitted: { [weak self] _ in self?._login() }),
            Chrome.vgap(12), WikiAppearance.field(_passwordField, placeholder: "Password", obscure: true, onSubmitted: { [weak self] _ in self?._login() }),
            Chrome.vgap(20), FilledButton(onPressed: { [weak self] in self?._login() }, child: Text("Sign in")),
        ]
        if let e = _loginError { rows += [Chrome.vgap(14), Text(e, style: WikiAppearance.text(15, color: Color(0xFFC42B1C)))] }
        return ColoredBox(color: WikiAppearance.paper, child: Column(crossAxisAlignment: .stretch, children: [
            _brandHeader(), Expanded(child: Center(child: SingleChildScrollView(child: Padding(padding: EdgeInsets(all: 24), child:
                Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 480), child: DecoratedBox(
                    decoration: BoxDecoration(color: WikiAppearance.white, border: Border.all(color: WikiAppearance.line), borderRadius: BorderRadius.circular(10)),
                    child: Padding(padding: EdgeInsets(all: _compact ? 24 : 36), child:
                        Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows))))))))),
        ]))
    }

    private func _sidebar(_ fluent: FluentThemeData) -> Widget {
        let ink = WikiAppearance.ink
        var header: [Widget] = [
            Padding(padding: EdgeInsets(all: 20), child: DecoratedBox(
                decoration: BoxDecoration(color: WikiAppearance.blue, borderRadius: BorderRadius.circular(9)),
                child: Padding(padding: EdgeInsets(all: 20), child: Column(crossAxisAlignment: .start, children: [
                    Text("YOUR TEAM / WIKI", style: WikiAppearance.text(12, bold: true, color: WikiAppearance.white)),
                    Chrome.vgap(12), Text(_space?.name ?? "Knowledge", style: WikiAppearance.text(25, bold: true, color: WikiAppearance.white)),
                ])))),
            Padding(padding: EdgeInsets(horizontal: 20), child: FilledButton(
                onPressed: { [weak self] in self?.setState { self?._newTitleOpen.toggle() } }, child: Text("New page +"))),
            Chrome.vgap(16),
        ]
        if _newTitleOpen {
            header.append(Padding(padding: EdgeInsets(left: 20, top: 0, right: 20, bottom: 12), child:
                WikiAppearance.field(_newTitleField, placeholder: "New page title", autofocus: true, onSubmitted: { [weak self] t in self?._createPage(t) })))
        }
        header.append(Padding(padding: EdgeInsets(left: 20, top: 0, right: 20, bottom: 16), child:
            WikiAppearance.field(_searchField, placeholder: "Search pages", onChanged: { [weak self] t in self?._search(t) },
                onSubmitted: { [weak self] t in self?._search(t) })))
        if _spaces.count > 1 {
            header.append(Padding(padding: EdgeInsets(left: 12, top: 0, right: 12, bottom: 6), child: Wrap(spacing: 6, children: _spaces.map { s in
                HyperlinkButton(onPressed: { [weak self] in self?._open(route: "/s/\(s.key)", push: true) },
                                child: Text(s.key, style: fluent.typography.caption?.copyWith(color: s.key == _space?.key ? ink : WikiAppearance.muted)))
            })))
        }
        // The tree, flattened depth-first with its depth.
        var rows: [(WikiPageNode, Int)] = []
        var byParent: [String?: [WikiPageNode]] = [:]
        for n in _tree { byParent[n.parent, default: []].append(n) }
        func walk(_ parent: String?, _ depth: Int, _ seen: inout Set<String>) {
            for n in (byParent[parent] ?? []).sorted(by: { ($0.position, $0.title) < ($1.position, $1.title) }) where !seen.contains(n.id) {
                seen.insert(n.id)
                rows.append((n, depth))
                walk(n.id, depth + 1, &seen)
            }
        }
        var seen = Set<String>()
        walk(nil, 0, &seen)
        // Orphans (parent deleted or outside the space) come last.
        for n in _tree where !seen.contains(n.id) { rows.append((n, 0)) }
        let current = _page?.id
        if let hits = _hits {
            // Search results stand in for the tree while a query is typed.
            let results: Widget = hits.isEmpty
                ? Padding(padding: EdgeInsets(left: 12, top: 8, right: 12, bottom: 8), child: Text("Nothing found.", style: fluent.typography.caption?.copyWith(color: WikiAppearance.muted)))
                : ListView(key: ValueKey("hits-\(hits.map(\.id).joined())"), itemCount: hits.count) { [weak self] _, i in
                    let hit = hits[i]
                    return Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0), child: FlyoutListTile(
                        onPressed: { self?._open(route: "/s/\(hit.space)/p/\(hit.id)/\(hit.slug)", push: true) },
                        text: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
                            Text(hit.title, style: fluent.typography.bodyStrong, softWrap: false),
                            Text(hit.snippet, style: fluent.typography.caption?.copyWith(color: WikiAppearance.muted), maxLines: 2),
                        ]),
                        margin: EdgeInsets(left: 0, top: 0, right: 0, bottom: 1),
                        selected: hit.id == current))
                }
            return SizedBox(width: _compact ? nil : 288, height: nil, child: DecoratedBox(
                decoration: BoxDecoration(color: WikiAppearance.white,
                                          border: Border(right: BorderSide(color: WikiAppearance.line, width: 1))),
                child: Column(crossAxisAlignment: .stretch, children: header + [Expanded(child: results)])))
        }
        let list = ListView(key: ValueKey("\(rows.count)-\(current ?? "")-\(_tree.map(\.title).joined())"), itemCount: rows.count) { [weak self] _, i in
            let (node, depth) = rows[i]
            return Padding(padding: EdgeInsets(left: 8 + Double(depth) * 14, top: 0, right: 8, bottom: 0),
                           child: FlyoutListTile(
                               onPressed: { self?._loadPage(node.id, push: true) },
                               text: Text(node.title, style: (node.id == current ? fluent.typography.bodyStrong : fluent.typography.body)?.copyWith(color: node.id == current ? WikiAppearance.blue : ink), softWrap: false),
                               margin: EdgeInsets(left: 0, top: 0, right: 0, bottom: 1),
                               selected: node.id == current))
        }
        var footer: [Widget] = []
        if let u = _user {
            footer.append(Padding(padding: EdgeInsets(left: 12, top: 6, right: 12, bottom: 10), child: Row(children: [
                Expanded(child: Text(u.name, style: fluent.typography.caption?.copyWith(color: WikiAppearance.muted), softWrap: false)),
                HyperlinkButton(onPressed: { [weak self] in
                    self?.session.logout { self?.setState { self?._needLogin = true; self?._user = nil } }
                }, child: Text("Sign out", style: fluent.typography.caption)),
            ])))
        }
        return SizedBox(width: _compact ? nil : 288, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(color: WikiAppearance.white,
                                      border: Border(right: BorderSide(color: WikiAppearance.line, width: 1))),
            child: Column(crossAxisAlignment: .stretch, children: header + [Expanded(child: list)] + footer)))
    }

    private func _header(_ fluent: FluentThemeData) -> Widget {
        let ink = WikiAppearance.ink
        var items: [Widget] = []
        if let page = _page {
            if page.version < page.tip {
                items.append(Text("Viewing version \(page.version) of \(page.tip)", style: fluent.typography.caption?.copyWith(color: WikiAppearance.muted)))
                items.append(Chrome.gap(12))
                items.append(Button(onPressed: { [weak self] in self?._loadPage(page.id, push: false) }, child: Text("Back to latest")))
                items.append(Chrome.gap(8))
                items.append(FilledButton(onPressed: { [weak self] in self?._restore() }, child: Text("Restore this version")))
            } else if _confirmDelete {
                items.append(Text("Delete \"\(page.title)\"? Its children move up a level.", style: fluent.typography.caption?.copyWith(color: WikiAppearance.muted)))
                items.append(Chrome.gap(12))
                items.append(Button(onPressed: { [weak self] in self?.setState { self?._confirmDelete = false } }, child: Text("Keep")))
                items.append(Chrome.gap(8))
                items.append(FilledButton(onPressed: { [weak self] in self?._deletePage() }, child: Text("Delete")))
            } else {
                if let other = _otherLock {
                    items.append(Row(children: [Icon(FluentSystemIcons.lock, size: 14, color: WikiAppearance.muted), Chrome.gap(4),
                                                Text("\(other.userName) is editing", style: fluent.typography.caption?.copyWith(color: WikiAppearance.muted))]))
                    items.append(Chrome.gap(12))
                }
                items.append(HyperlinkButton(onPressed: { [weak self] in
                    guard let self else { return }
                    self.setState { self._historyOpen.toggle() }
                    if self._historyOpen { self._loadVersions() }
                }, child: Text("History · v\(page.version)", style: fluent.typography.caption?.copyWith(color: _historyOpen ? ink : WikiAppearance.muted))))
                items.append(Chrome.gap(8))
                if page.id != _space?.homePage {
                    items.append(Button(onPressed: { [weak self] in self?.setState { self?._confirmDelete = true } }, child: Text("Delete")))
                    items.append(Chrome.gap(8))
                }
                items.append(Button(onPressed: { [weak self] in self?._exportDocx() }, child: Text("Export .docx")))
                items.append(Chrome.gap(8))
                items.append(Button(onPressed: { [weak self] in self?._importDocx() }, child: Text("Import…")))
                items.append(Chrome.gap(8))
                items.append(FilledButton(onPressed: _otherLock == nil ? { [weak self] in self?._beginEdit() } : nil, child: Text("Edit")))
            }
        }
        let title: Widget = Text(_page?.title ?? (_loading ? "Loading…" : "Choose a page"), style: WikiAppearance.text(_compact ? 25 : 32, bold: true))
        return DecoratedBox(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: WikiAppearance.line, width: 1))),
            child: Padding(padding: EdgeInsets(all: _compact ? 16 : 24), child: Column(crossAxisAlignment: .stretch, children: [
                Text(_space?.name ?? "Wiki", style: WikiAppearance.text(13, bold: true, color: WikiAppearance.blue)),
                Chrome.vgap(8), title, Chrome.vgap(18), Wrap(spacing: 0, runSpacing: 8, children: items),
            ])))
    }

    private func _historyPane(_ fluent: FluentThemeData) -> Widget {
        let ink = WikiAppearance.ink
        let current = _page?.version
        let pageID = _page?.id
        let list = ListView(key: ValueKey("versions-\(_versions.count)-\(current ?? 0)"), itemCount: _versions.count) { [weak self] _, i in
            let v = self?._versions[i]
            guard let v else { return SizedBox(width: 0, height: 0, child: nil) }
            let when = v.createdAt.prefix(16).replacingAll("T", with: " ")
            return Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0), child: FlyoutListTile(
                onPressed: { if let pageID { self?._loadPage(pageID, version: v.version, push: false) } },
                text: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
                    Text("Version \(v.version)\(v.base.map { " (from \($0))" } ?? "")", style: v.version == current ? fluent.typography.bodyStrong : fluent.typography.body, softWrap: false),
                    Text("\(v.author ?? "?") · \(when)", style: fluent.typography.caption?.copyWith(color: WikiAppearance.muted), softWrap: false),
                ]),
                margin: EdgeInsets(left: 0, top: 0, right: 0, bottom: 1),
                selected: v.version == current))
        }
        return SizedBox(width: _compact ? nil : 272, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(color: WikiAppearance.white,
                                      border: Border(left: BorderSide(color: WikiAppearance.line, width: 1))),
            child: Column(crossAxisAlignment: .stretch, children: [
                Padding(padding: EdgeInsets(left: 12, top: 12, right: 12, bottom: 6), child: Row(children: [
                    Expanded(child: Text("History", style: fluent.typography.subtitle?.copyWith(color: ink))),
                    HyperlinkButton(onPressed: { [weak self] in self?.setState { self?._historyOpen = false } }, child: Text("Close", style: fluent.typography.caption)),
                ])),
                Expanded(child: list),
            ])))
    }

    private func _editor(_ fluent: FluentThemeData) -> Widget {
        let page = Color(0xFFFFFFFF)
        let theme = _theme
        theme.textColor = Color(0xFF1B1B1B)
        theme.caretColor = theme.textColor
        theme.selectionColor = WikiAppearance.blue.withOpacity(0.20)
        return RichEditable(
            controller: _controller, theme: theme,
            padding: EdgeInsets(left: _compact ? 20 : 40, top: 28, right: _compact ? 20 : 40, bottom: 120),
            focusNode: _editorFocus, autofocus: false,
            backgroundColor: page, zoom: 1.0,
            pageSetup: nil, pageColor: page,
            onShortcut: { [weak self] key, mods in self?._shortcut(key, mods) ?? false },
            onLinkActivate: { [weak self] link in self?._followLink(link) }
        )
    }

    /// A link inside a page: one of ours opens in place, anything else is
    /// left to the browser or the host.
    private func _followLink(_ link: String) {
        if let r = link.findRange(of: "/s/"), link.hasPrefix(session.base) || link.hasPrefix("/") {
            _open(route: String(link[r.lowerBound...]), push: true)
            return
        }
        #if os(WASI)
        WebHistory.push(link)   // (a cross-origin link: let the tab go there)
        #else
        setState { _status = link }
        #endif
    }

    private func _statusBar(_ fluent: FluentThemeData) -> Widget {
        let text = _status ?? (_editing ? (_dirty ? "Editing — unsaved changes" : "Editing") : (_page.map { "Last saved by \($0.author ?? "?")" } ?? ""))
        return DecoratedBox(
            decoration: BoxDecoration(color: WikiAppearance.white, border: Border(top: BorderSide(color: WikiAppearance.line, width: 1))),
            child: Padding(padding: EdgeInsets(left: 20, top: 12, right: 20, bottom: 12),
                           child: Text(text, style: fluent.typography.caption?.copyWith(color: WikiAppearance.muted), softWrap: false)))
    }
}
