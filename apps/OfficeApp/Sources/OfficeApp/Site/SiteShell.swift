// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The site reader: the page tree, search, and the page drawn by the
// Writer in read mode — the wiki's look, over a SiteStore. Over the
// cloned repository (the native app, `--site <dir>`) it also edits: Edit
// is the whole Writer on the page (HostedDocument), New page adds to
// site.json, Publish builds, commits and pushes. Over the built site (a
// tab on GitHub Pages) it only reads.

import Flutter
import FlutterSwiftBridge
import Foundation
#if os(WASI)
import FlutterWeb
#endif

final class SiteRoot: StatelessWidget {
    let store: SiteStore
    let route: String
    init(store: SiteStore, route: String) {
        self.store = store
        self.route = route
        super.init()
    }
    override func build(_ context: any BuildContext) -> Widget {
        FluentApp(theme: WikiAppearance.theme, themeMode: .light,
                  home: ButtonTheme(data: WikiAppearance.buttons, child: SiteShell(store: store, route: route)),
                  title: "Starling Site")
    }
}

final class SiteShell: StatefulWidget {
    let store: SiteStore
    let route: String
    init(store: SiteStore, route: String) {
        self.store = store
        self.route = route
        super.init()
    }
    override func createState() -> State<StatefulWidget> { SiteShellState() }
}

final class SiteShellState: State<StatefulWidget> {
    private var store: SiteStore { (widget as! SiteShell).store }

    private var _manifest: SiteManifest?
    private var _slug: String?
    private let _controller = RichDocumentController()
    private let _theme: RichTextTheme = OfficeSession(kind: .document).theme
    private var _loading = false
    private var _status: String?

    // Editing (the whole Writer) and publishing, over a writable store.
    private var _editing = false
    private var _writer: OfficeShell?
    private var _publishOpen = false
    private var _publishing = false
    private let _publishMessage = TextEditingController()
    private var _newTitleOpen = false
    private let _newTitleField = TextEditingController()

    // Search: nil when not searching, [] when nothing matched.
    private let _searchField = TextEditingController()
    private var _entries: [SiteSearchEntry]?
    private var _hits: [(entry: SiteSearchEntry, snippet: String)]?

    // Layout.
    private var _compact = false
    private var _navigationOpen = false
    private var _previousMetrics: (() -> Void)?

    // MARK: Lifecycle

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
        _installDebug()
        #if os(WASI)
        WebHistory.onRouteChanged = { [weak self] route in self?._open(route: route, push: false) }
        #endif
        store.manifest { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let m):
                self.setState { self._manifest = m }
                self._open(route: (self.widget as! SiteShell).route, push: false)
            case .failure(let e): self.setState { self._status = "\(e)" }
            }
        }
    }

    override func dispose() {
        PlatformDispatcher.instance.onMetricsChanged = _previousMetrics
        super.dispose()
    }

    /// `starling.debug('text')`: the open page's text; 'slug': which page.
    /// (Writer installs its own while editing; put back on return.)
    private func _installDebug() {
        hostDebugQuery = { [weak self] kind in
            guard let self else { return nil }
            switch kind {
            case "text": return SiteFiles.plainText(self._controller.document)
            case "slug": return self._slug ?? ""
            case "title": return self._manifest?.title
            default: return nil
            }
        }
    }

    // MARK: Pages

    private func _open(route: String, push: Bool) {
        guard let m = _manifest else { return }
        let slug = SiteFiles.slug(ofRoute: route, base: m.base)
        _load(slug.isEmpty ? m.home : slug, push: push)
    }

    private func _load(_ slug: String, push: Bool) {
        guard let m = _manifest else { return }
        if _editing { _cancelEdit(reload: false) }
        guard m.node(slug) != nil else {
            setState { _slug = nil; _status = "There is no page \"\(slug)\" on this site."; _loading = false }
            _controller.load(RichDocument())
            return
        }
        setState { _loading = true }
        store.page(slug) { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let doc):
                self.setState {
                    self._slug = slug
                    self._loading = false
                    self._status = nil
                    if self._compact { self._navigationOpen = false }
                }
                self._controller.load(doc)
                self._controller.readOnly = true
                // The tab's (window's) title follows the page, as the shell
                // page's did before the app started.
                let title = m.node(slug)?.title ?? slug
                hostSetWindowTitle?(title == m.title ? title : "\(title) — \(m.title)")
                #if os(WASI)
                if push { WebHistory.push(m.route(slug)) }
                #endif
            case .failure(let e):
                self.setState { self._loading = false; self._status = "\(e)" }
            }
        }
    }

    private func _refreshManifest(then: @escaping () -> Void = {}) {
        store.manifest { [weak self] r in
            guard let self else { return }
            if case .success(let m) = r { self.setState { self._manifest = m }; self._entries = nil }
            then()
        }
    }

    // MARK: Editing

    private func _beginEdit() {
        guard let slug = _slug, let m = _manifest, store.canEdit, !_editing else { return }
        let doc = _controller.document
        let title = m.node(slug)?.title ?? slug
        let writer = OfficeShell(initialPath: nil, hosted: HostedDocument(
            title: title, document: doc, ownerName: "site",
            save: { [weak self] doc, done in
                guard let self else { done("The site reader went away."); return }
                self.store.save(slug, doc) { [weak self] message in
                    if message == nil { self?._controller.load(doc) }
                    done(message)
                }
            },
            close: { [weak self] in self?._cancelEdit(reload: true) }))
        setState { _editing = true; _writer = writer }
    }

    private func _cancelEdit(reload: Bool) {
        setState { _editing = false; _writer = nil }
        _controller.readOnly = true
        _installDebug()
        if reload, let slug = _slug { _load(slug, push: false) }
    }

    private func _createPage(_ title: String) {
        let t = title.trimmingWhitespace()
        guard !t.isEmpty else { return }
        store.createPage(title: t, under: _slug) { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let slug):
                self.setState { self._newTitleOpen = false; self._newTitleField.text = "" }
                self._refreshManifest { self._load(slug, push: true) }
            case .failure(let e): self.setState { self._status = "\(e)" }
            }
        }
    }

    private func _publish() {
        guard !_publishing else { return }
        setState { _publishing = true; _status = "Building and pushing…" }
        store.publish(message: _publishMessage.text) { [weak self] message in
            guard let self else { return }
            self.setState {
                self._publishing = false
                self._status = message ?? "Published."
                if message == nil { self._publishOpen = false; self._publishMessage.text = "" }
            }
        }
    }

    // MARK: Search

    private func _search(_ query: String) {
        let q = query.trimmingWhitespace().lowercased()
        guard !q.isEmpty else { setState { _hits = nil }; return }
        if let entries = _entries { _applySearch(q, entries); return }
        store.search { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let entries): self._entries = entries; self._applySearch(q, entries)
            case .failure(let e): self.setState { self._status = "\(e)"; self._hits = [] }
            }
        }
    }

    private func _applySearch(_ q: String, _ entries: [SiteSearchEntry]) {
        var hits: [(SiteSearchEntry, String)] = []
        for e in entries {
            let text = e.text
            if e.title.lowercased().containsSubstring(q) {
                hits.append((e, String(text.prefix(90))))
            } else if let r = text.lowercased().findRange(of: q) {
                // The match with some of its line around it.
                let lower = text.lowercased()
                let offset = lower.distance(from: lower.startIndex, to: r.lowerBound)
                let start = max(0, offset - 40)
                let snippet = String(text.dropFirst(start).prefix(120)).split(separator: "\n").first.map(String.init) ?? ""
                hits.append((e, (start > 0 ? "…" : "") + snippet))
            }
        }
        setState { _hits = hits.map { (entry: $0.0, snippet: $0.1) } }
    }

    // MARK: Build

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        if let view = PlatformDispatcher.instance.implicitView {
            _compact = view.physicalSize.width / view.devicePixelRatio < 900
        }
        // Editing: the whole Writer, nothing of the site's chrome around it.
        if _editing, let writer = _writer { return writer }
        let main = Padding(padding: EdgeInsets(all: _compact ? 12 : 24), child: DecoratedBox(
            decoration: BoxDecoration(color: WikiAppearance.white, border: Border.all(color: WikiAppearance.line),
                                      borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: .stretch, children: [
                _header(fluent), Expanded(child: _reader()), _statusBar(fluent),
            ])))
        let content: Widget
        if _compact && _navigationOpen { content = _sidebar(fluent) }
        else {
            var row: [Widget] = []
            if !_compact { row.append(_sidebar(fluent)) }
            row.append(Expanded(child: main))
            content = Row(crossAxisAlignment: .stretch, children: row)
        }
        return ColoredBox(color: WikiAppearance.paper, child: Column(crossAxisAlignment: .stretch, children: [
            _brandHeader(), Expanded(child: content),
        ]))
    }

    private func _brandHeader() -> Widget {
        var items: [Widget] = [
            SizedBox(width: 30, height: 30, child: DecoratedBox(
                decoration: BoxDecoration(color: WikiAppearance.blue, borderRadius: BorderRadius.circular(7)),
                child: Center(child: SizedBox(width: 13, height: 18, child: ColoredBox(color: WikiAppearance.white))))),
            Chrome.gap(10), Text(_manifest?.title ?? "Site", style: WikiAppearance.text(23, bold: true)),
            Expanded(child: SizedBox(width: 0, height: 0, child: nil)),
        ]
        if _compact {
            items.append(Button(onPressed: { [weak self] in self?.setState { self?._navigationOpen.toggle() } },
                                child: Text(_navigationOpen ? "Close" : "Pages")))
        } else {
            items.append(Text(store.canEdit ? "LOCAL COPY" : "PUBLISHED", style: WikiAppearance.text(13, bold: true, color: WikiAppearance.muted)))
        }
        return SizedBox(height: 72, child: ColoredBox(color: WikiAppearance.white, child:
            Padding(padding: EdgeInsets(horizontal: _compact ? 20 : 32), child: Row(children: items))))
    }

    private func _sidebar(_ fluent: FluentThemeData) -> Widget {
        let ink = WikiAppearance.ink
        var header: [Widget] = [
            Padding(padding: EdgeInsets(all: 20), child: DecoratedBox(
                decoration: BoxDecoration(color: WikiAppearance.blue, borderRadius: BorderRadius.circular(9)),
                child: Padding(padding: EdgeInsets(all: 20), child: Column(crossAxisAlignment: .start, children: [
                    Text(store.canEdit ? "YOUR SITE / LOCAL" : "YOUR SITE", style: WikiAppearance.text(12, bold: true, color: WikiAppearance.white)),
                    Chrome.vgap(12), Text(_manifest?.title ?? "Site", style: WikiAppearance.text(25, bold: true, color: WikiAppearance.white)),
                ])))),
        ]
        if store.canEdit {
            header.append(Padding(padding: EdgeInsets(horizontal: 20), child: FilledButton(
                onPressed: { [weak self] in self?.setState { self?._newTitleOpen.toggle() } }, child: Text("New page +"))))
            header.append(Chrome.vgap(16))
            if _newTitleOpen {
                header.append(Padding(padding: EdgeInsets(left: 20, top: 0, right: 20, bottom: 12), child:
                    WikiAppearance.field(_newTitleField, placeholder: "New page title", autofocus: true,
                                         onSubmitted: { [weak self] t in self?._createPage(t) })))
            }
        }
        header.append(Padding(padding: EdgeInsets(left: 20, top: 0, right: 20, bottom: 16), child:
            WikiAppearance.field(_searchField, placeholder: "Search pages", onChanged: { [weak self] t in self?._search(t) },
                                 onSubmitted: { [weak self] t in self?._search(t) })))
        let current = _slug
        let list: Widget
        if let hits = _hits {
            list = hits.isEmpty
                ? Padding(padding: EdgeInsets(left: 12, top: 8, right: 12, bottom: 8), child: Text("Nothing found.", style: fluent.typography.caption?.copyWith(color: WikiAppearance.muted)))
                : ListView(key: ValueKey("hits-\(hits.map(\.entry.slug).joined())"), itemCount: hits.count) { [weak self] _, i in
                    let hit = hits[i]
                    return Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0), child: FlyoutListTile(
                        onPressed: { self?._load(hit.entry.slug, push: true) },
                        text: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
                            Text(hit.entry.title, style: fluent.typography.bodyStrong, softWrap: false),
                            Text(hit.snippet, style: fluent.typography.caption?.copyWith(color: WikiAppearance.muted), maxLines: 2),
                        ]),
                        margin: EdgeInsets(left: 0, top: 0, right: 0, bottom: 1),
                        selected: hit.entry.slug == current))
                }
        } else {
            let rows = _manifest?.flattened() ?? []
            list = ListView(key: ValueKey("tree-\(rows.count)-\(current ?? "")-\(rows.map(\.node.title).joined())"), itemCount: rows.count) { [weak self] _, i in
                let (node, depth) = rows[i]
                return Padding(padding: EdgeInsets(left: 8 + Double(depth) * 14, top: 0, right: 8, bottom: 0), child: FlyoutListTile(
                    onPressed: { self?._load(node.slug, push: true) },
                    text: Text(node.title, style: (node.slug == current ? fluent.typography.bodyStrong : fluent.typography.body)?.copyWith(color: node.slug == current ? WikiAppearance.blue : ink), softWrap: false),
                    margin: EdgeInsets(left: 0, top: 0, right: 0, bottom: 1),
                    selected: node.slug == current))
            }
        }
        return SizedBox(width: _compact ? nil : 288, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(color: WikiAppearance.white,
                                      border: Border(right: BorderSide(color: WikiAppearance.line, width: 1))),
            child: Column(crossAxisAlignment: .stretch, children: header + [Expanded(child: list)])))
    }

    private func _header(_ fluent: FluentThemeData) -> Widget {
        let title = _slug.flatMap { _manifest?.node($0)?.title } ?? (_loading ? "Loading…" : (_manifest == nil ? "Loading site…" : "Choose a page"))
        var items: [Widget] = []
        if store.canEdit, _slug != nil {
            if _publishOpen {
                items.append(SizedBox(width: _compact ? 220 : 360, height: 46, child:
                    WikiAppearance.field(_publishMessage, placeholder: "Commit message", autofocus: true, onSubmitted: { [weak self] _ in self?._publish() })))
                items.append(Chrome.gap(8))
                items.append(Button(onPressed: _publishing ? nil : { [weak self] in self?.setState { self?._publishOpen = false } }, child: Text("Cancel")))
                items.append(Chrome.gap(8))
                items.append(FilledButton(onPressed: _publishing ? nil : { [weak self] in self?._publish() }, child: Text(_publishing ? "Publishing…" : "Build, commit and push")))
            } else {
                items.append(Button(onPressed: { [weak self] in self?.setState { self?._publishOpen = true } }, child: Text("Publish…")))
                items.append(Chrome.gap(8))
                items.append(FilledButton(onPressed: { [weak self] in self?._beginEdit() }, child: Text("Edit")))
            }
        }
        return DecoratedBox(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: WikiAppearance.line, width: 1))),
            child: Padding(padding: EdgeInsets(all: _compact ? 16 : 24), child: Column(crossAxisAlignment: .stretch, children: [
                Text(_manifest?.title ?? "Site", style: WikiAppearance.text(13, bold: true, color: WikiAppearance.blue)),
                Chrome.vgap(8), Text(title, style: WikiAppearance.text(_compact ? 25 : 32, bold: true)),
            ] + (items.isEmpty ? [] : [Chrome.vgap(18), Wrap(spacing: 0, runSpacing: 8, children: items)]))))
    }

    private func _reader() -> Widget {
        let page = Color(0xFFFFFFFF)
        let theme = _theme
        theme.textColor = Color(0xFF1B1B1B)
        theme.caretColor = theme.textColor
        theme.selectionColor = WikiAppearance.blue.withOpacity(0.20)
        return RichEditable(
            controller: _controller, theme: theme,
            padding: EdgeInsets(left: _compact ? 20 : 40, top: 28, right: _compact ? 20 : 40, bottom: 120),
            autofocus: false, backgroundColor: page, zoom: 1.0, pageSetup: nil, pageColor: page,
            onLinkActivate: { [weak self] link in self?._followLink(link) })
    }

    /// A link inside a page: one of this site's routes opens in place;
    /// anything else is the browser's.
    private func _followLink(_ link: String) {
        if let m = _manifest, link.hasPrefix("/") || link.hasPrefix(m.base) {
            let slug = SiteFiles.slug(ofRoute: link, base: m.base)
            if m.node(slug) != nil { _load(slug, push: true); return }
        }
        #if os(WASI)
        WebHistory.push(link)
        #else
        setState { _status = link }
        #endif
    }

    private func _statusBar(_ fluent: FluentThemeData) -> Widget {
        let text = _status ?? (store.canEdit ? "Local copy — Publish builds docs/, commits and pushes." : "")
        return DecoratedBox(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: WikiAppearance.line, width: 1))),
            child: Padding(padding: EdgeInsets(left: 20, top: 10, right: 20, bottom: 10),
                           child: Text(text, style: fluent.typography.caption?.copyWith(color: WikiAppearance.muted), softWrap: false, overflow: .ellipsis)))
    }
}
