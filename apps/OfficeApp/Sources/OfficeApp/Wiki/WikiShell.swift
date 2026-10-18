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
        FluentApp(theme: OfficeAppearance.theme(.light), darkTheme: OfficeAppearance.theme(.dark), themeMode: .light,
                  home: WikiShell(session: WikiSession(base: base), route: route), title: "Wiki")
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
    private let _searchField = TextEditingController()
    private var _hits: [WikiHit]? = nil      // nil: not searching; []: nothing found
    private var _searchGeneration = 0

    override func initState() {
        super.initState()
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
                    self._loading = false
                    self._status = nil
                    self._otherLock = nil
                    self._titleField.text = page.title
                }
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
                self.setState { self._lock = lock; self._editing = true; self._dirty = false; self._otherLock = nil }
                self._controller.readOnly = false
                self._editorFocus.requestFocus()
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

    private func _save() {
        guard let page = _page, _editing else { return }
        let doc = _controller.document
        guard let body = WikiSession.encodeBody(doc) else { setState { _status = "Could not encode the page." }; return }
        let title = _titleField.text.trimmingWhitespace(newlines: false)
        setState { _loading = true }
        session.save(page.id, title: title.isEmpty ? page.title : title, body: body, plainText: WikiSession.plainText(doc),
                     links: WikiSession.linkedPages(doc), base: page.version, lockToken: _lock?.token) { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let saved):
                self.setState { self._page = saved; self._dirty = false; self._loading = false; self._status = "Saved version \(saved.version)." }
                self._refreshTree()
            case .failure(let e):
                self.setState { self._loading = false }
                if e.status == 409 { self.setState { self._status = "Someone saved this page while you edited. Copy your changes, then Cancel and Edit again." } }
                else { self._report(e) }
            }
        }
    }

    private func _finishEdit() {
        guard _editing else { return }
        if _dirty { _save() }
        _cancelEdit(reload: !_dirty)
    }

    private func _cancelEdit(reload: Bool) {
        _heartbeat += 1
        if let page = _page, let lock = _lock { session.unlock(page.id, token: lock.token) {} }
        setState { _editing = false; _lock = nil; _dirty = false }
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
        case "s": if _editing { _save() }; return true
        case "e": if !_editing { _beginEdit() }; return true
        default: return false
        }
    }

    // MARK: Build

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        if _needLogin { return _loginView(fluent) }
        let sidebar = _sidebar(fluent)
        var column: [Widget] = [_header(fluent)]
        if _editing { column.append(_toolbar(fluent)) }
        column.append(Expanded(child: _editor(fluent)))
        column.append(_statusBar(fluent))
        let main = Column(crossAxisAlignment: .stretch, children: column)
        return ColoredBox(color: fluent.scaffoldBackgroundColor, child: Row(crossAxisAlignment: .stretch, children: [
            sidebar,
            Expanded(child: main),
        ]))
    }

    private func _loginView(_ fluent: FluentThemeData) -> Widget {
        let ink = OfficeAppearance.ink(fluent)
        var rows: [Widget] = [
            Text("Sign in", style: fluent.typography.title?.copyWith(color: ink)),
            Chrome.vgap(16),
            SizedBox(width: 280, height: 32, child: FluentTextBox(controller: _loginField, placeholderText: "Login", onSubmitted: { [weak self] _ in self?._login() })),
            Chrome.vgap(8),
            SizedBox(width: 280, height: 32, child: PasswordBox(controller: _passwordField, placeholderText: "Password", onSubmitted: { [weak self] _ in self?._login() })),
            Chrome.vgap(12),
            FilledButton(onPressed: { [weak self] in self?._login() }, child: Text("Sign in")),
        ]
        if let e = _loginError { rows += [Chrome.vgap(12), Text(e, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C)))] }
        return ColoredBox(color: OfficeAppearance.canvas(fluent), child: Center(child: DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent), border: Border.all(color: OfficeAppearance.border(fluent)),
                                      borderRadius: BorderRadius.circular(8)),
            child: Padding(padding: EdgeInsets(left: 32, top: 28, right: 32, bottom: 28),
                           child: Column(mainAxisSize: .min, crossAxisAlignment: .center, children: rows)))))
    }

    private func _sidebar(_ fluent: FluentThemeData) -> Widget {
        let ink = OfficeAppearance.ink(fluent)
        var header: [Widget] = [
            Padding(padding: EdgeInsets(left: 12, top: 12, right: 12, bottom: 4), child: Row(children: [
                Expanded(child: Text(_space?.name ?? "Wiki", style: fluent.typography.subtitle?.copyWith(color: ink), softWrap: false)),
                FlatButton(child: Icon(FluentSystemIcons.add, size: 16, color: ink), tip: "New page", width: 28, height: 28,
                           action: { [weak self] in self?.setState { self?._newTitleOpen.toggle() } }),
            ])),
        ]
        if _newTitleOpen {
            header.append(Padding(padding: EdgeInsets(left: 12, top: 4, right: 12, bottom: 8), child: SizedBox(width: nil, height: 30, child: FluentTextBox(
                controller: _newTitleField, placeholderText: "New page title", onSubmitted: { [weak self] t in self?._createPage(t) }, autofocus: true))))
        }
        header.append(Padding(padding: EdgeInsets(left: 12, top: 2, right: 12, bottom: 8), child: SizedBox(width: nil, height: 30, child: FluentTextBox(
            controller: _searchField, placeholderText: "Search pages", onChanged: { [weak self] t in self?._search(t) },
            onSubmitted: { [weak self] t in self?._search(t) }))))
        if _spaces.count > 1 {
            header.append(Padding(padding: EdgeInsets(left: 12, top: 0, right: 12, bottom: 6), child: Wrap(spacing: 6, children: _spaces.map { s in
                HyperlinkButton(onPressed: { [weak self] in self?._open(route: "/s/\(s.key)", push: true) },
                                child: Text(s.key, style: fluent.typography.caption?.copyWith(color: s.key == _space?.key ? ink : fluent.resources.textFillColorSecondary)))
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
                ? Padding(padding: EdgeInsets(left: 12, top: 8, right: 12, bottom: 8), child: Text("Nothing found.", style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)))
                : ListView(key: ValueKey("hits-\(hits.map(\.id).joined())"), itemCount: hits.count) { [weak self] _, i in
                    let hit = hits[i]
                    return Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0), child: FlyoutListTile(
                        onPressed: { self?._open(route: "/s/\(hit.space)/p/\(hit.id)/\(hit.slug)", push: true) },
                        text: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
                            Text(hit.title, style: fluent.typography.bodyStrong, softWrap: false),
                            Text(hit.snippet, style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary), maxLines: 2),
                        ]),
                        margin: EdgeInsets(left: 0, top: 0, right: 0, bottom: 1),
                        selected: hit.id == current))
                }
            return SizedBox(width: 260, height: nil, child: DecoratedBox(
                decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                          border: Border(right: BorderSide(color: OfficeAppearance.border(fluent), width: 1))),
                child: Column(crossAxisAlignment: .stretch, children: header + [Expanded(child: results)])))
        }
        let list = ListView(key: ValueKey("\(rows.count)-\(current ?? "")-\(_tree.map(\.title).joined())"), itemCount: rows.count) { [weak self] _, i in
            let (node, depth) = rows[i]
            return Padding(padding: EdgeInsets(left: 8 + Double(depth) * 14, top: 0, right: 8, bottom: 0),
                           child: FlyoutListTile(
                               onPressed: { self?._loadPage(node.id, push: true) },
                               text: Text(node.title, style: node.id == current ? fluent.typography.bodyStrong : fluent.typography.body, softWrap: false),
                               margin: EdgeInsets(left: 0, top: 0, right: 0, bottom: 1),
                               selected: node.id == current))
        }
        var footer: [Widget] = []
        if let u = _user {
            footer.append(Padding(padding: EdgeInsets(left: 12, top: 6, right: 12, bottom: 10), child: Row(children: [
                Expanded(child: Text(u.name, style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary), softWrap: false)),
                HyperlinkButton(onPressed: { [weak self] in
                    self?.session.logout { self?.setState { self?._needLogin = true; self?._user = nil } }
                }, child: Text("Sign out", style: fluent.typography.caption)),
            ])))
        }
        return SizedBox(width: 260, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                      border: Border(right: BorderSide(color: OfficeAppearance.border(fluent), width: 1))),
            child: Column(crossAxisAlignment: .stretch, children: header + [Expanded(child: list)] + footer)))
    }

    private func _header(_ fluent: FluentThemeData) -> Widget {
        let ink = OfficeAppearance.ink(fluent)
        var items: [Widget] = []
        if _editing {
            items.append(Expanded(child: SizedBox(width: nil, height: 32, child: FluentTextBox(controller: _titleField, placeholderText: "Title"))))
        } else {
            items.append(Expanded(child: Text(_page?.title ?? (_loading ? "Loading…" : ""), style: fluent.typography.title?.copyWith(color: ink), softWrap: false)))
        }
        items.append(Chrome.gap(12))
        if let page = _page {
            if _editing {
                items.append(Button(onPressed: { [weak self] in self?._cancelEdit(reload: true) }, child: Text("Cancel")))
                items.append(Chrome.gap(8))
                items.append(FilledButton(onPressed: { [weak self] in self?._finishEdit() }, child: Text(_dirty ? "Save" : "Done")))
            } else {
                if let other = _otherLock {
                    items.append(Row(children: [Icon(FluentSystemIcons.lock, size: 14, color: fluent.resources.textFillColorSecondary), Chrome.gap(4),
                                                Text("\(other.userName) is editing", style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary))]))
                    items.append(Chrome.gap(12))
                }
                items.append(Text("v\(page.version)", style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)))
                items.append(Chrome.gap(12))
                items.append(Button(onPressed: { [weak self] in self?._exportDocx() }, child: Text("Export .docx")))
                items.append(Chrome.gap(8))
                items.append(Button(onPressed: { [weak self] in self?._importDocx() }, child: Text("Import…")))
                items.append(Chrome.gap(8))
                items.append(FilledButton(onPressed: _otherLock == nil ? { [weak self] in self?._beginEdit() } : nil, child: Text("Edit")))
            }
        }
        return DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent), border: Border(bottom: BorderSide(color: OfficeAppearance.border(fluent), width: 1))),
            child: Padding(padding: EdgeInsets(left: 20, top: 10, right: 16, bottom: 10), child: Row(children: items)))
    }

    private func _toolbar(_ fluent: FluentThemeData) -> Widget {
        let ink = OfficeAppearance.ink(fluent)
        let c = _controller
        func b(_ label: String, _ tip: String, _ action: @escaping () -> Void) -> Widget {
            FlatButton(child: Text(label, style: fluent.typography.bodyStrong?.copyWith(color: ink)), tip: tip, width: nil, height: 28, action: action)
        }
        return DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent), border: Border(bottom: BorderSide(color: OfficeAppearance.border(fluent), width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 4, right: 12, bottom: 4), child: Row(children: [
                b("B", "Bold (⌘B)") { c.toggleBold() }, Chrome.gap(2),
                b("I", "Italic (⌘I)") { c.toggleItalic() }, Chrome.gap(2),
                b("U", "Underline (⌘U)") { c.toggleUnderline() }, Chrome.gap(12),
                b("H1", "Heading 1") { c.setHeading(1) }, Chrome.gap(2),
                b("H2", "Heading 2") { c.setHeading(2) }, Chrome.gap(2),
                b("H3", "Heading 3") { c.setHeading(3) }, Chrome.gap(2),
                b("¶", "Normal text") { c.setHeading(nil) }, Chrome.gap(12),
                b("•", "Bulleted list") { c.toggleList(.bullet) }, Chrome.gap(2),
                b("1.", "Numbered list") { c.toggleList(.numbered) }, Chrome.gap(12),
                b("↶", "Undo (⌘Z)") { c.undo() }, Chrome.gap(2),
                b("↷", "Redo (⇧⌘Z)") { c.redo() },
            ])))
    }

    private func _editor(_ fluent: FluentThemeData) -> Widget {
        let page = Color(0xFFFFFFFF)
        let theme = _theme
        theme.textColor = Color(0xFF1B1B1B)
        theme.caretColor = theme.textColor
        theme.selectionColor = fluent.accentColor.defaultBrushFor(.light).withOpacity(0.25)
        return RichEditable(
            controller: _controller, theme: theme,
            padding: EdgeInsets(left: 72, top: 28, right: 72, bottom: 120),
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
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent), border: Border(top: BorderSide(color: OfficeAppearance.border(fluent), width: 1))),
            child: Padding(padding: EdgeInsets(left: 16, top: 4, right: 16, bottom: 4),
                           child: Text(text, style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary), softWrap: false)))
    }
}
