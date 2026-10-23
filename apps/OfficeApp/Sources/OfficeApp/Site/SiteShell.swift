// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The site reader: the page tree, search, and the page drawn by the
// Writer in read mode — the wiki's look, over a SiteStore. A page that
// came from a paged file is shown as pages (headers, footers, page
// numbers) on a desktop and as flow on a phone, with a Contents panel
// whose entries carry page numbers, a link to any paragraph, and a PDF
// that is the same painter. Over the cloned repository (the native app,
// `--site <dir>`) it also edits: Edit is the whole Writer on the page
// (HostedDocument), New page adds to site.json, Publish builds, commits
// and pushes. Over the built site (a tab on GitHub Pages) it only reads.

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
    let startEditing: Bool
    /// Set when Writer opened the site from Backstage: "Close site" returns there.
    let onLeave: (() -> Void)?
    init(store: SiteStore, route: String, startEditing: Bool = false, onLeave: (() -> Void)? = nil) {
        self.store = store
        self.route = route
        self.startEditing = startEditing
        self.onLeave = onLeave
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
    private var _pageSetup: PageSetup?
    private var _loading = false
    private var _status: String?
    private var _publicationStatus = "Checking saved publication…"
    private var _publicationCheck = 0
    #if !os(WASI)
    private var _reviewOpen = false
    private var _reviewedPublication: SiteReviewedPublication?
    private var _detailsOpen = false
    private var _liveCheck = 0
    private var _checkingLive = false
    private var _liveMessage: String?
    private var _verifiedPublication: SiteLivePublication.Snapshot?
    private var _copyingPageLink = false
    private var _heldDraft = false
    private var _unpublishedSlugs: Set<String> = []
    #endif

    // Pages or flow: the reader's choice, else pages on a desktop and flow
    // on a phone, and flow always for a page with no page setup.
    private var _viewPages: Bool?
    private var _pageInfo = (page: 1, count: 1)
    private var showPages: Bool { _pageSetup != nil && (_viewPages ?? !_compact) }

    // Contents: the headings, each with the page it starts on in page view.
    private var _toc: [(index: Int, level: Int, text: String, page: Int?)] = []
    private var _tocOpen = false
    /// A paragraph the route named (`#p=<id>`), revealed once its page is open.
    private var _pendingParagraph: UInt32?

    // Editing (the whole Writer) and publishing, over a writable store.
    private var _editing = false
    private var _editOnNextLoad = false
    private var _writer: OfficeShell?
    private var _hostingOpen = false
    private var _publishOpen = false
    private var _publishing = false
    private var _publishIssue: SitePublishIssue?
    private var _publishStage: SitePublishStage = .checking
    private var _publishControl: SitePublishControl?
    private var _stoppingUpload = false
    private let _publishMessage = TextEditingController()
    private var _newTitleOpen = false
    private let _newTitleField = TextEditingController()
    private var _importOpen = false
    private var _updateImport = false
    private var _revision: SiteRevision?
    private var _previewOriginal = false
    private var _pageActionsOpen = false
    private var _aboutPublication = false
    private var _renameOpen = false
    private let _renameField = TextEditingController()
    private var _confirmDelete = false
    private var _confirmHome: (slug: String, previous: String)?

    // Find in the page.
    private var _findOpen = false
    // The published reader's tools (link, downloads, history, find) sit
    // behind "More": a reader sees the page, the contents and the view
    // toggle, not a toolbar — on a phone the toolbar wrapped to three rows.
    private var _moreOpen = false
    private let _findField = TextEditingController()
    private var _findStatus = ""

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
        _editOnNextLoad = (widget as! SiteShell).startEditing
        _ = OfficeFonts.register()
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

    /// `starling.debug(kind)` for scripts: 'text' the open page's text,
    /// 'slug' which page, 'title' the site's, 'view' pages or flow, 'pages'
    /// the page count, 'toc' one heading a line as "level\tpage\ttext",
    /// 'caret' the id of the paragraph the caret is in. (Writer installs
    /// its own while editing; put back on return.)
    private func _installDebug() {
        hostDebugQuery = { [weak self] kind in
            guard let self else { return nil }
            switch kind {
            case "text": return SiteFiles.plainText(self._controller.document)
            case "slug": return self._slug ?? ""
            case "title": return self._manifest?.title
            case "view": return self.showPages ? "pages" : "flow"
            case "status": return self._status ?? ""
            case "selection": return self._controller.selectedText
            case "pages": return "\(self._pageInfo.count)"
            case "page": return "\(self._pageInfo.page)"
            case "toc": return self._toc.map { "\($0.level)\t\($0.page ?? 0)\t\($0.text)" }.joined(separator: "\n")
            case "caret":
                let i = self._controller.caret.paragraph
                return self._controller.document.paragraphs.indices.contains(i) ? "\(self._controller.document.paragraphs[i].id)" : ""
            default: return nil
            }
        }
    }

    // MARK: Pages

    /// `#p=<id>` at the end of a route: the paragraph to open at.
    static func paragraph(inRoute route: String) -> UInt32? {
        guard let r = route.findRange(of: "#p=") else { return nil }
        var digits = ""
        for ch in route[r.upperBound...] { if ch.isNumber { digits.append(ch) } else { break } }
        return UInt32(digits)
    }

    private func _open(route: String, push: Bool) {
        guard let m = _manifest else { return }
        let slug = SiteFiles.slug(ofRoute: route, base: m.base)
        _pendingParagraph = Self.paragraph(inRoute: route)
        _load(slug.isEmpty ? m.home : slug, push: push)
    }

    private func _load(_ slug: String, push: Bool) {
        if _publishing { return }
        _revision = nil
        _confirmHome = nil
        _confirmDelete = false
        _renameOpen = false
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
            case .success(let page):
                self.setState {
                    self._slug = slug
                    self._pageSetup = page.pageSetup
                    self._loading = false
                    self._status = nil
                    self._pageInfo = (1, 1)
                    if self._compact { self._navigationOpen = false }
                }
                self._controller.load(page.document)
                #if !os(WASI)
                if let local = self.store as? LocalSiteStore {
                    SiteRecent().remember(repo: local.repo, slug: slug)
                }
                #endif
                self._controller.readOnly = true
                self._computeContents()
                self._refreshPublicationStatus()
                // The tab's (window's) title follows the page, as the shell
                // page's did before the app started.
                let title = m.node(slug)?.title ?? slug
                hostSetWindowTitle?(title == m.title ? title : "\(title) — \(m.title)")
                #if os(WASI)
                if push { WebHistory.push(m.route(slug)) }
                // The text layer for screen readers follows the page.
                let downloads = m.exports == true ? m.exportPaths(slug) : nil
                if let content = SiteReaderText(document: page.document, title: title, route: m.base + slug + "/", downloads: downloads,
                                                history: m.historyURL(slug)).json() {
                    WebAccessibility.setDocumentContent(content)
                } else {
                    WebAccessibility.setDocumentText(SiteTextLayer.lines(of: page.document), downloads: downloads)
                }
                #endif
                if let id = self._pendingParagraph { self._pendingParagraph = nil; self._reveal(paragraphID: id) }
                if self._editOnNextLoad {
                    self._editOnNextLoad = false
                    self._beginEdit()
                }
            case .failure(let e):
                self.setState { self._loading = false; self._status = "\(e)" }
            }
        }
    }

    /// The headings, with the page each starts on when the page is paged:
    /// a layout of its own, the one the page view makes, asked per heading.
    private func _computeContents() {
        let doc = _controller.document
        let outline = NavigationPane.outline(doc)
        var pages: [Int: Int] = [:]
        if let setup = _pageSetup, !outline.isEmpty {
            let layout = RichLayout(theme: _theme, paragraphCount: doc.paragraphs.count)
            layout.scale = 1.0
            layout.pageSetup = setup
            layout.width = setup.columnWidth * _theme.pixelsPerPoint
            layout.ensureLaidOut(doc)
            for h in outline { if let p = layout.pageNumber(ofParagraph: h.index) { pages[h.index] = p } }
        }
        setState { _toc = outline.map { (index: $0.index, level: $0.level, text: $0.text, page: pages[$0.index]) } }
    }

    /// Open at a paragraph: scroll it to the top and select it, so it reads
    /// as "here".
    private func _reveal(paragraphID id: UInt32) {
        let doc = _controller.document
        let matches = doc.paragraphs.indices.filter { doc.paragraphs[$0].id == id }
        guard id != 0, matches.count == 1 else {
            setState { _status = "This passage link could not be matched to a single paragraph." }
            return
        }
        let i = matches[0]
        // Selected with the caret at its START, and that start scrolled to
        // the top: a selection whose caret sat at the end would be revealed
        // by its end, and the paragraph would land at the foot of the view.
        let slug = _slug
        let apply = { [weak self] in
            guard let self else { return }
            self._controller.pendingReveal = .top
            self._controller.selection = RichSelection(anchor: RichPosition(paragraph: i, offset: doc.paragraphs[i].length),
                                                       focus: RichPosition(paragraph: i, offset: 0))
        }
        apply()
        // The editable lays the new document out on its next frame; until
        // then a reveal has no layout to measure against and is lost. Asked
        // again once it has one (a collapsed caret first, so the second set
        // is a change the editable hears).
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self] in
            guard let self, self._slug == slug, self._controller.document.paragraphs.indices.contains(i) else { return }
            self._controller.selection = RichSelection(anchor: RichPosition(paragraph: i, offset: 0), focus: RichPosition(paragraph: i, offset: 0))
            apply()
        }
    }

    /// The address bar becomes a link to the paragraph the caret is in.
    private func _linkToParagraph() {
        guard let m = _manifest, let slug = _slug else { return }
        let doc = _controller.document
        let i = _controller.caret.paragraph
        guard doc.paragraphs.indices.contains(i), doc.paragraphs[i].id != 0 else {
            setState { _status = "Click into a paragraph first." }
            return
        }
        let link = m.paragraphRoute(slug, id: doc.paragraphs[i].id)
        #if os(WASI)
        WebHistory.push(link, replace: true)
        WebClipboard.copyLocation()
        setState { _status = "Link to this paragraph copied; the address bar has it too." }
        #else
        if store is LocalSiteStore {
            _copyPublishedPageLink(paragraph: doc.paragraphs[i].id)
        } else if let base = URL(string: store.base), base.scheme == "https" || base.scheme == "http",
                  let url = URL(string: link, relativeTo: base)?.absoluteURL {
            Clipboard.setData(ClipboardData(text: url.absoluteString))
            setState { _status = "Link to this paragraph copied." }
        }
        #endif
    }

    /// The page as a .docx: a download in a tab, a file in Documents natively.
    private func _exportDocx() {
        guard let slug = _slug else { return }
        // The build left a static copy beside the page: a link, instantly.
        if let m = _manifest, m.exports == true, !store.canEdit { hostOpenURL?(m.exportPaths(slug).docx); return }
        do {
            let data = try OfficeFormats.encode(_controller.document, as: "docx", pageSetup: _pageSetup ?? .letter)
            #if os(WASI)
            WebFiles.download(data, as: slug + ".docx")
            setState { _status = "Exported \(slug).docx" }
            #else
            let target = homeDirectory() + "/Documents/" + slug + ".docx"
            try data.write(to: URL(fileURLWithPath: target), options: .atomic)
            setState { _status = "Exported \(target)" }
            #endif
        } catch { setState { _status = "Could not export: \(error)" } }
    }

    private func _isUnpublished(_ slug: String) -> Bool {
        #if !os(WASI)
        return _unpublishedSlugs.contains(slug)
        #else
        return false
        #endif
    }

    /// The page's history: its commits on GitHub, when the site names its repository.
    private func _openHistory() {
        if let slug = _slug, _isUnpublished(slug) {
            setState { _status = "This chapter is a local draft and has no published history." }
            return
        }
        guard let repo = _manifest?.repository, let slug = _slug else { return }
        let base = repo.hasSuffix("/") ? String(repo.dropLast()) : repo
        hostOpenURL?(base + "/commits/main/" + SiteFiles.pagePath(slug))
    }

    private func _exportPDF() {
        guard let m = _manifest, let slug = _slug else { return }
        if m.exports == true, !store.canEdit { hostOpenURL?(m.exportPaths(slug).pdf); setState { _status = "Opened \(slug).pdf" }; return }
        let title = m.node(slug)?.title ?? slug
        let target = homeDirectory() + "/Documents/" + slug + ".pdf"
        let ok = PdfExport.write(_controller.document, pageSetup: _pageSetup ?? .letter, theme: _theme, to: target, title: title)
        setState { _status = ok ? "Exported \(slug).pdf" : "Could not write the PDF" }
    }

    private func _refreshManifest(then: @escaping () -> Void = {}) {
        store.manifest { [weak self] r in
            guard let self else { return }
            if case .success(let m) = r {
                self.setState { self._manifest = m }
                self._entries = nil
                self._search(self._searchField.text)
                self._refreshPublicationStatus()
            }
            then()
        }
    }

    private func _refreshPublicationStatus() {
        #if !os(WASI)
        guard let local = store as? LocalSiteStore else { return }
        _clearLiveCheck()
        _publicationCheck += 1
        setState { _publicationStatus = "Checking saved publication…" }
        let check = _publicationCheck, repo = local.repo, out = local.out, slug = _slug
        let worker = Thread { [weak self] in
            let message = SitePublicationState.status(repo: repo, out: out).message
            let held = slug.flatMap { try? SiteDrafts.load(repo: repo, slug: $0) } != nil
            let unpublished = Set((try? SiteUnpublishedDrafts.loadAll(repo: repo))?.map(\.slug) ?? [])
            DispatchQueue.main.async {
                guard let self, self.mounted, self._publicationCheck == check else { return }
                self.setState { self._publicationStatus = message; self._heldDraft = held; self._unpublishedSlugs = unpublished }
            }
        }
        worker.name = "Starling publication status"
        worker.stackSize = 8 * 1024 * 1024
        worker.start()
        #endif
    }

    #if !os(WASI)
    private func _clearLiveCheck() {
        _liveCheck += 1
        setState { _checkingLive = false; _liveMessage = nil; _verifiedPublication = nil; _copyingPageLink = false }
    }

    private func _checkLiveWebsite() {
        guard let local = store as? LocalSiteStore, !_publishing, !_checkingLive else { return }
        _refreshPublicationStatus()
        let check = _liveCheck, repo = local.repo, out = local.out
        setState { _checkingLive = true; _liveMessage = "Checking the website's uploaded version…" }
        DispatchQueue.global().async { [weak self] in
            func finish(_ result: Result<URL, SiteError>, expected: SiteLivePublication.Snapshot?) {
                // A second publish or changed destination must invalidate an in-flight response.
                let stillCurrent = expected != nil && (try? SiteLivePublication.snapshot(repo: repo, out: out)) == expected
                DispatchQueue.main.async {
                    guard let self, self.mounted, self._liveCheck == check else { return }
                    self.setState {
                        self._checkingLive = false
                        switch result {
                        case .success where stillCurrent:
                            self._verifiedPublication = expected
                            let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
                            self._liveMessage = "Website confirmed the last uploaded version at \(time). Open it to review before sharing."
                        case .success:
                            self._liveMessage = "Publishing details changed during this check. Check the website again."
                        case .failure(let error): self._liveMessage = error.description
                        }
                    }
                }
            }
            do {
                let expected = try SiteLivePublication.snapshot(repo: repo, out: out)
                SiteLivePublication.check(expected) { finish($0, expected: expected) }
            } catch {
                finish(.failure(SiteError("\(error)")), expected: nil)
            }
        }
    }

    private func _useWebsiteLink(copy: Bool) {
        guard let expected = _verifiedPublication, let local = store as? LocalSiteStore else { return }
        let check = _liveCheck, repo = local.repo, out = local.out
        DispatchQueue.global().async { [weak self] in
            let current = try? SiteLivePublication.snapshot(repo: repo, out: out)
            DispatchQueue.main.async {
                guard let self, self.mounted, self._liveCheck == check else { return }
                guard current == expected else {
                    self._clearLiveCheck()
                    self.setState { self._liveMessage = "Publishing details changed. Check the website again before sharing." }
                    return
                }
                let link = expected.website.absoluteString
                if copy {
                    Clipboard.setData(ClipboardData(text: link))
                    self.setState { self._status = "Website link copied." }
                } else { hostOpenURL?(link) }
            }
        }
    }

    private func _copyPublishedPageLink(paragraph: UInt32? = nil) {
        guard let local = store as? LocalSiteStore, let slug = _slug, !_publishing, !_copyingPageLink else { return }
        guard let expected = _verifiedPublication else {
            setState { _status = "Choose Check live website before sharing this page or paragraph." }
            return
        }
        let check = _liveCheck
        setState { _copyingPageLink = true; _status = "Checking the published page…" }
        let worker = Thread { [weak self] in
            let result = Result { try SitePublishedLink.prepare(repo: local.repo, out: local.out, verified: expected, slug: slug, paragraph: paragraph) }
            DispatchQueue.main.async {
                guard let self, self.mounted, self._liveCheck == check, self._slug == slug else { return }
                self.setState {
                    self._copyingPageLink = false
                    switch result {
                    case .success(let url):
                        Clipboard.setData(ClipboardData(text: url.absoluteString))
                        self._status = paragraph == nil ? "Link to the verified published page copied." : "Link to the verified published paragraph copied."
                    case .failure(let error): self._status = "\(error)"
                    }
                }
            }
        }
        worker.name = "Starling published page link"
        worker.stackSize = 8 * 1024 * 1024
        worker.start()
    }
    #endif

    private func _websiteControls() -> [Widget] {
        #if !os(WASI)
        guard store is LocalSiteStore else { return [] }
        var buttons: [Widget] = [
            Button(onPressed: _publishing || _checkingLive ? nil : { [weak self] in self?._checkLiveWebsite() }, child: Text(_checkingLive ? "Checking website…" : "Check live website")),
            Button(onPressed: _publishing ? nil : { [weak self] in self?.setState { self?._detailsOpen = true } }, child: Text("Publication details…")),
        ]
        if _verifiedPublication != nil {
            buttons.append(Button(onPressed: { [weak self] in self?._useWebsiteLink(copy: false) }, child: Text("Open website")))
            buttons.append(Button(onPressed: { [weak self] in self?._useWebsiteLink(copy: true) }, child: Text("Copy website link")))
            buttons.append(Button(onPressed: _copyingPageLink ? nil : { [weak self] in self?._copyPublishedPageLink() }, child: Text(_copyingPageLink ? "Checking page…" : "Copy page link")))
        }
        return (_liveMessage.map { [Chrome.vgap(8), Text($0, style: WikiAppearance.text(14, color: WikiAppearance.muted))] } ?? [])
            + [Chrome.vgap(12), Wrap(spacing: 8, runSpacing: 8, children: buttons)]
        #else
        return []
        #endif
    }

    // MARK: Editing

    private func _beginEdit() {
        guard let slug = _slug, let m = _manifest, store.canEdit, !_editing else { return }
        let doc = _controller.document
        let title = m.node(slug)?.title ?? slug
        let writer = OfficeShell(initialPath: nil, hosted: HostedDocument(
            title: title, document: doc, pageSetup: _pageSetup, ownerName: "publication",
            save: { [weak self] doc, setup, done in
                guard let self else { done("The site reader went away."); return }
                self.store.save(slug, SitePage(document: doc, pageSetup: setup)) { [weak self] message in
                    if message == nil { self?._controller.load(doc); self?._pageSetup = setup }
                    done(message)
                }
            },
            close: { [weak self] in self?._cancelEdit(reload: true) }, returnLabel: "Back to preview",
            initialSelection: _controller.selection))
        setState { _editing = true; _writer = writer }
    }

    private func _cancelEdit(reload: Bool) {
        setState { _editing = false; _writer = nil }
        _controller.readOnly = true
        _installDebug()
        if reload, let slug = _slug { _load(slug, push: false) }
    }

    private func _createPage(_ title: String) {
        guard !_publishing else { return }
        let t = title.trimmingWhitespace()
        guard !t.isEmpty else { return }
        store.createPage(title: t, under: _slug) { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let slug):
                self.setState { self._newTitleOpen = false; self._newTitleField.text = ""; self._editOnNextLoad = true }
                self._refreshManifest { self._load(slug, push: true) }
            case .failure(let e): self.setState { self._status = "\(e)" }
            }
        }
    }

    // MARK: Import, rename, delete, find

    private func _importFile(_ path: String) {
        setState { _importOpen = false }
        do {
            var opened = try OfficeFormats.read(path)
            if _updateImport, let slug = _slug {
                _updateImport = false
                store.previewUpdate(slug, page: SitePage(document: opened.document, pageSetup: opened.pageSetup)) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let revision):
                        self.setState { self._revision = revision; self._previewOriginal = false }
                        self._showRevision()
                    case .failure(let error): self.setState { self._status = "\(error)" }
                    }
                }
                return
            }
            opened.document.assignParagraphIDs()
            let title = path.lastPathComponent.deletingPathExtension
            store.importPage(title: title, page: SitePage(document: opened.document, pageSetup: opened.pageSetup), under: _slug) { [weak self] r in
                guard let self else { return }
                switch r {
                case .success(let slug): self._refreshManifest { self._load(slug, push: true) }
                case .failure(let e): self.setState { self._status = "\(e)" }
                }
            }
        } catch { setState { _status = "Could not read \(path.lastPathComponent): \(error)" } }
    }

    private func _showRevision() {
        guard let revision = _revision else { return }
        let page = _previewOriginal ? revision.original : revision.replacement
        _controller.load(page.document)
        _controller.readOnly = true
        setState {
            _pageSetup = page.pageSetup
            _pageInfo = (1, 1)
            _status = (_previewOriginal ? "Current saved document. " : "Revised document preview. ") + revision.summary
        }
        _computeContents()
    }

    private func _applyRevision() {
        guard let revision = _revision else { return }
        store.applyUpdate(revision) { [weak self] error in
            guard let self else { return }
            if let error { self.setState { self._status = error }; return }
            self._entries = nil
            self._load(revision.slug, push: false)
            self.setState { self._status = "Saved locally. Review the chapter’s inclusion before publishing." }
        }
    }

    private func _rename() {
        guard let slug = _slug else { return }
        let title = _renameField.text.trimmingWhitespace()
        guard !title.isEmpty else { return }
        store.rename(slug, to: title) { [weak self] message in
            guard let self else { return }
            if let message { self.setState { self._status = message }; return }
            self.setState { self._renameOpen = false }
            self._refreshManifest { [weak self] in
                guard let self, let m = self._manifest else { return }
                hostSetWindowTitle?("\(title) — \(m.title)")
            }
        }
    }

    private func _movePage(by: Int) {
        guard let slug = _slug else { return }
        store.move(slug, by: by) { [weak self] message in
            guard let self else { return }
            if let message { self.setState { self._status = message }; return }
            self._refreshManifest()
        }
    }

    private func _deletePage() {
        guard let slug = _slug, let m = _manifest else { return }
        store.delete(slug) { [weak self] message in
            guard let self else { return }
            self.setState { self._confirmDelete = false }
            if let message { self.setState { self._status = message }; return }
            self._refreshManifest { [weak self] in
                guard let self else { return }
                self._load(self._manifest?.home ?? m.home, push: true)
                self.setState { self._status = "Deleted the page." }
            }
        }
    }

    private func _setHome() {
        guard let choice = _confirmHome else { return }
        store.setHome(choice.slug, replacing: choice.previous) { [weak self] message in
            guard let self else { return }
            self.setState {
                self._confirmHome = nil
                self._status = message ?? "Home page saved locally. Publish to update the website."
            }
            self._refreshManifest()
        }
    }

    private func _findNext(backwards: Bool) {
        let q = _findField.text
        guard !q.isEmpty else { return }
        if let sel = _controller.find(q, backwards: backwards) {
            _controller.pendingReveal = .visible
            _controller.selection = sel
            setState { _findStatus = "" }
        } else {
            setState { _findStatus = "No matches" }
        }
    }

    private func _shortcut(_ key: KeyData, _ mods: KeyModifiers) -> Bool {
        guard mods.contains(.primary), let letter = KeyChordTracker.letter(key.logical) else { return false }
        switch letter {
        case "f": setState { _findOpen = true }; return true
        case "g": if _findOpen { _findNext(backwards: mods.contains(.shift)) }; return _findOpen
        default: return false
        }
    }

    private func _openPublish() {
        setState {
            _publishOpen = true
            #if !os(WASI)
            _reviewedPublication = nil
            _reviewOpen = store is LocalSiteStore
            #endif
        }
    }

    private func _publish() {
        guard !_publishing else { return }
        #if !os(WASI)
        if store is LocalSiteStore, _reviewedPublication == nil {
            setState { _reviewOpen = true; _publishOpen = true }
            return
        }
        let control = SitePublishControl(reviewedPublication: _reviewedPublication)
        // Each attempt consumes the review. Retrying after a local commit or a
        // setup change returns to review instead of silently accepting new files.
        _reviewedPublication = nil
        _clearLiveCheck()
        #else
        let control = SitePublishControl()
        #endif
        setState { _publishControl = control; _stoppingUpload = false; _publishing = true; _publishIssue = nil; _publishStage = .checking; _status = _publishStage.message }
        store.publish(message: _publishMessage.text, progress: { [weak self] stage in
            guard let self, self.mounted, self._publishing else { return }
            self.setState { self._publishStage = stage; self._status = stage.message }
        }, control: control) { [weak self] issue in
            guard let self, self.mounted else { return }
            self.setState {
                self._publishControl = nil
                self._stoppingUpload = false
                self._publishing = false
                self._publishIssue = issue
                self._status = issue?.title ?? "Sent to hosting. Choose Check live website to confirm the uploaded version."
                if issue == nil { self._publishOpen = false; self._publishMessage.text = "" }
            }
            self._refreshPublicationStatus()
        }
    }

    private func _publishFeedback() -> [Widget] {
        guard store.canEdit else { return [] }
        if _publishing {
            return [Chrome.vgap(12), Text(_stoppingUpload && _publishStage == .uploading ? "Stopping upload…" : _publishStage.message, style: WikiAppearance.text(15, bold: true))]
        }
        guard let issue = _publishIssue else { return [] }
        var rows: [Widget] = [Chrome.vgap(14), Text(issue.title, style: WikiAppearance.text(16, bold: true)),
                              Chrome.vgap(6), Text(issue.guidance, style: WikiAppearance.text(14, color: WikiAppearance.muted))]
        if let url = issue.helpURL {
            rows += [Chrome.vgap(8), Wrap(children: [Button(onPressed: { hostOpenURL?(url) }, child: Text("GitHub sign-in help"))])]
        }
        #if !os(WASI)
        if issue.kind == .setup, store is LocalSiteStore {
            rows += [Chrome.vgap(8), Wrap(children: [Button(onPressed: { [weak self] in
                self?.setState { self?._publishOpen = true; self?._hostingOpen = true }
            }, child: Text("Finish publishing setup"))])]
        }
        #endif
        return rows
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
        var viewWidth = 1400.0
        if let view = PlatformDispatcher.instance.implicitView {
            viewWidth = view.physicalSize.width / view.devicePixelRatio
            _compact = viewWidth < 900
        }
        // Editing: the whole Writer, nothing of the site's chrome around it.
        if _editing, let writer = _writer { return writer }
        if _aboutPublication, let details = _manifest?.details {
            return SitePublicationAbout(title: _manifest?.title ?? "Publication", details: details,
                                        onClose: { [weak self] in self?.setState { self?._aboutPublication = false } })
        }
        #if !os(WASI)
        if _detailsOpen, let local = store as? LocalSiteStore {
            return SitePublicationDetailsPanel(repo: local.repo, onClose: { [weak self] in
                guard let self else { return }
                self.setState { self._detailsOpen = false }
                self._refreshManifest()
            })
        }
        if _hostingOpen, let local = store as? LocalSiteStore {
            return SiteHostingPanel(store: local, onClose: { [weak self] in
                guard let self else { return }
                self.setState {
                    self._hostingOpen = false
                    self._reviewedPublication = nil
                    if self._publishOpen { self._reviewOpen = true }
                }
                self._refreshManifest()
            })
        }
        if _reviewOpen, let local = store as? LocalSiteStore {
            return SitePublishReviewPanel(store: local, onBack: { [weak self] in
                guard let self else { return }
                self.setState { self._reviewOpen = false; self._publishOpen = false }
                self._refreshManifest { [weak self] in
                    if let self, let manifest = self._manifest {
                        let slug = self._slug ?? manifest.home
                        self._load(manifest.node(slug) == nil ? manifest.home : slug, push: false)
                    }
                }
            }, onContinue: { [weak self] reviewed in
                guard let self else { return }
                self.setState {
                    self._reviewOpen = false; self._publishOpen = true
                    self._reviewedPublication = reviewed
                    self._publishIssue = nil
                    if let config = try? SiteBuilder.readConfig(local.repo),
                       (config.repository ?? "").trimmingWhitespace().isEmpty || (config.url ?? "").trimmingWhitespace().isEmpty {
                        self._hostingOpen = true
                    }
                }
                self._refreshManifest { [weak self] in
                    if let self, let manifest = self._manifest {
                        let slug = self._slug ?? manifest.home
                        self._load(manifest.node(slug) == nil ? manifest.home : slug, push: false)
                    }
                }
            }, onPreview: { [weak self] slug, paragraphID in
                guard let self else { return }
                self.setState { self._reviewOpen = false; self._publishOpen = false }
                self._refreshManifest { [weak self] in
                    guard let self else { return }
                    self._pendingParagraph = paragraphID
                    self._load(slug, push: true)
                }
            })
        }
        if _importOpen {
            // The file panel, in the reader's place: a document to become a page.
            return ColoredBox(color: WikiAppearance.paper, child: Column(crossAxisAlignment: .stretch, children: [
                _brandHeader(),
                Expanded(child: Padding(padding: EdgeInsets(all: 24), child: FluentFilePanel(
                    mode: .open, initialDirectory: (store as? LocalSiteStore)?.repo ?? homeDirectory() + "/Documents",
                    extensions: _updateImport ? ["docx"] : OfficeFormats.readable,
                    onDone: { [weak self] path in
                        guard let self else { return }
                        if let path { self._importFile(path) } else { self.setState { self._importOpen = false } }
                    }))),
            ]))
        }
        #endif
        var body: [Widget] = [Expanded(child: _reader(viewWidth: viewWidth))]
        if _tocOpen, !_compact { body.append(_contents(fluent)) }
        let main = Padding(padding: EdgeInsets(all: _compact ? 12 : 24), child: DecoratedBox(
            decoration: BoxDecoration(color: WikiAppearance.white, border: Border.all(color: WikiAppearance.line),
                                      borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: .stretch, children: [
                _header(fluent),
                Expanded(child: _tocOpen && _compact ? _contents(fluent) : Row(crossAxisAlignment: .stretch, children: body)),
                _statusBar(fluent),
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
        } else if let leave = (widget as! SiteShell).onLeave {
            items.append(Text("LOCAL COPY", style: WikiAppearance.text(13, bold: true, color: WikiAppearance.muted)))
            items.append(Chrome.gap(16))
            items.append(Button(onPressed: _publishing ? nil : { leave() }, child: Text("Close publication")))
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
                onPressed: _publishing ? nil : { [weak self] in self?.setState { self?._newTitleOpen.toggle() } }, child: Text("New draft +"))))
            header.append(Chrome.vgap(16))
            if _newTitleOpen {
                header.append(Padding(padding: EdgeInsets(left: 20, top: 0, right: 20, bottom: 12), child:
                    WikiAppearance.field(_newTitleField, placeholder: "New chapter title", autofocus: true,
                                         onSubmitted: { [weak self] t in self?._createPage(t) })))
                header.append(Padding(padding: EdgeInsets(left: 20, top: 0, right: 20, bottom: 12), child:
                    Wrap(spacing: 8, runSpacing: 8, children: [
                        FilledButton(onPressed: { [weak self] in
                            guard let self else { return }; self._createPage(self._newTitleField.text)
                        }, child: Text("Create draft")),
                        Button(onPressed: { [weak self] in self?.setState { self?._newTitleOpen = false } }, child: Text("Cancel")),
                    ])))
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
                    text: Text(node.title + (self?._isUnpublished(node.slug) == true ? " · Draft" : ""), style: (node.slug == current ? fluent.typography.bodyStrong : fluent.typography.body)?.copyWith(color: node.slug == current ? WikiAppearance.blue : ink), softWrap: false),
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
        if _slug != nil {
            let tools = store.canEdit || _moreOpen
            // A phone reads as flow; the toggle is for a desktop reader.
            if _pageSetup != nil, store.canEdit || !_compact {
                items.append(Button(onPressed: showPages ? nil : { [weak self] in self?.setState { self?._viewPages = true } }, child: Text(store.canEdit ? "Page preview" : "Pages")))
                items.append(Chrome.gap(4))
                items.append(Button(onPressed: showPages ? { [weak self] in self?.setState { self?._viewPages = false } } : nil, child: Text(store.canEdit ? "Reading view" : "Flow")))
                items.append(Chrome.gap(8))
            }
            if !_toc.isEmpty {
                items.append(Button(onPressed: { [weak self] in self?.setState { self?._tocOpen.toggle() } }, child: Text(_tocOpen ? "Hide contents" : "Contents")))
                items.append(Chrome.gap(8))
            }
            if !store.canEdit, !tools {
                items.append(Button(onPressed: { [weak self] in self?.setState { self?._moreOpen = true } }, child: Text("More")))
                items.append(Chrome.gap(8))
            }
        }
        if _slug != nil, store.canEdit || _moreOpen {
            items.append(Button(onPressed: { [weak self] in self?._linkToParagraph() }, child: Text("Link to paragraph")))
            items.append(Chrome.gap(8))
            items.append(Button(onPressed: { [weak self] in self?._exportPDF() }, child: Text("PDF")))
            items.append(Chrome.gap(4))
            items.append(Button(onPressed: { [weak self] in self?._exportDocx() }, child: Text("Word")))
            items.append(Chrome.gap(8))
            if _manifest?.repository != nil {
                items.append(Button(onPressed: { [weak self] in self?._openHistory() }, child: Text("History")))
                items.append(Chrome.gap(8))
            }
            if _manifest?.details?.hasContent == true {
                items.append(Button(onPressed: { [weak self] in self?.setState { self?._aboutPublication = true } }, child: Text("About publication")))
                items.append(Chrome.gap(8))
            }
            if _findOpen {
                items.append(SizedBox(width: _compact ? 180 : 240, height: 46, child:
                    WikiAppearance.field(_findField, placeholder: "Find in page", autofocus: true,
                                         onChanged: { [weak self] _ in self?._findNext(backwards: false) },
                                         onSubmitted: { [weak self] _ in self?._findNext(backwards: false) })))
                items.append(Chrome.gap(4))
                items.append(Button(onPressed: { [weak self] in self?._findNext(backwards: false) }, child: Text("Next")))
                items.append(Chrome.gap(4))
                items.append(Button(onPressed: { [weak self] in self?.setState { self?._findOpen = false; self?._findStatus = "" } }, child: Text("Close")))
                if !_findStatus.isEmpty {
                    items.append(Chrome.gap(8))
                    items.append(Text(_findStatus, style: fluent.typography.caption?.copyWith(color: WikiAppearance.muted)))
                }
            } else {
                items.append(Button(onPressed: { [weak self] in self?.setState { self?._findOpen = true } }, child: Text("Find")))
            }
            items.append(Chrome.gap(8))
            if !store.canEdit {
                items.append(Button(onPressed: { [weak self] in self?.setState { self?._moreOpen = false; self?._findOpen = false; self?._findStatus = "" } }, child: Text("Less")))
                items.append(Chrome.gap(8))
            }
        }
        if store.canEdit, _slug != nil {
            if let revision = _revision {
                items.append(Text("Review the revised document before replacing this page. Local edits will be replaced.", style: WikiAppearance.text(14)))
                items.append(Button(onPressed: { [weak self] in
                    guard let self else { return }
                    self.setState { self._previewOriginal.toggle() }
                    self._showRevision()
                }, child: Text(_previewOriginal ? "View revised" : "View current")))
                items.append(Button(onPressed: { [weak self] in self?._load(revision.slug, push: false) }, child: Text("Cancel update")))
                items.append(FilledButton(onPressed: { [weak self] in self?._applyRevision() }, child: Text("Apply update")))
            } else if _confirmHome != nil {
                items.append(Text("After publishing, links to the website's main address will open this page. Page order stays the same.", style: WikiAppearance.text(14)))
                items.append(Button(onPressed: { [weak self] in self?.setState { self?._confirmHome = nil } }, child: Text("Keep current home")))
                items.append(FilledButton(onPressed: { [weak self] in self?._setHome() }, child: Text("Set as home page")))
            } else if _confirmDelete {
                let title = _slug.flatMap { _manifest?.node($0)?.title } ?? ""
                items.append(Text("Delete \"\(title)\"? Its pages move up a level.", style: fluent.typography.caption?.copyWith(color: WikiAppearance.muted)))
                items.append(Chrome.gap(12))
                items.append(Button(onPressed: { [weak self] in self?.setState { self?._confirmDelete = false } }, child: Text("Keep")))
                items.append(Chrome.gap(8))
                items.append(FilledButton(onPressed: { [weak self] in self?._deletePage() }, child: Text("Delete")))
            } else if _renameOpen {
                items.append(SizedBox(width: _compact ? 220 : 320, height: 46, child:
                    WikiAppearance.field(_renameField, placeholder: "Title", autofocus: true, onSubmitted: { [weak self] _ in self?._rename() })))
                items.append(Chrome.gap(8))
                items.append(Button(onPressed: { [weak self] in self?.setState { self?._renameOpen = false } }, child: Text("Cancel")))
                items.append(Chrome.gap(8))
                items.append(FilledButton(onPressed: { [weak self] in self?._rename() }, child: Text("Rename")))
            } else if _publishOpen {
                #if !os(WASI)
                if store is LocalSiteStore {
                    items.append(Button(onPressed: _publishing ? nil : { [weak self] in self?.setState { self?._reviewOpen = true } }, child: Text("Review publication…")))
                    items.append(Chrome.gap(8))
                    items.append(Button(onPressed: _publishing ? nil : { [weak self] in self?.setState { self?._hostingOpen = true } }, child: Text("Publishing settings…")))
                    items.append(Chrome.gap(8))
                    items.append(Button(onPressed: _publishing ? nil : { [weak self] in self?._refreshPublicationStatus() }, child: Text("Check publication status")))
                    items.append(Chrome.gap(8))
                }
                #endif
                items.append(SizedBox(width: _compact ? 220 : 360, height: 46, child:
                    WikiAppearance.field(_publishMessage, placeholder: "What changed? (optional)", autofocus: true, enabled: !_publishing, onSubmitted: { [weak self] _ in self?._publish() })))
                items.append(Chrome.gap(8))
                if _publishing && _publishStage == .uploading {
                    items.append(Button(onPressed: _stoppingUpload ? nil : { [weak self] in
                        guard let self else { return }
                        self._publishControl?.cancel()
                        self.setState { self._stoppingUpload = true; self._status = "Stopping upload…" }
                    }, child: Text(_stoppingUpload ? "Stopping…" : "Stop upload")))
                } else {
                    items.append(Button(onPressed: _publishing ? nil : { [weak self] in self?.setState { self?._publishOpen = false } }, child: Text("Cancel")))
                }
                items.append(Chrome.gap(8))
                items.append(FilledButton(onPressed: _publishing ? nil : { [weak self] in self?._publish() }, child: Text(_publishing ? "Publishing…" : (_publishIssue?.retryTitle ?? "Publish"))))
            } else {
                #if !os(WASI)
                items.append(Button(onPressed: { [weak self] in self?.setState { self?._updateImport = false; self?._importOpen = true } }, child: Text("Add a Word draft…")))
                items.append(Chrome.gap(8))
                items.append(Button(onPressed: { [weak self] in self?.setState { self?._updateImport = true; self?._importOpen = true } }, child: Text("Update from Word…")))
                items.append(Chrome.gap(8))
                #endif
                items.append(Button(onPressed: { [weak self] in self?.setState { self?._pageActionsOpen.toggle() } }, child: Text(_pageActionsOpen ? "Hide page options" : "Page options")))
                items.append(Chrome.gap(8))
                if _pageActionsOpen {
                    items.append(Button(onPressed: { [weak self] in
                        guard let self else { return }
                        self._renameField.text = self._slug.flatMap { self._manifest?.node($0)?.title } ?? ""
                        self.setState { self._renameOpen = true }
                    }, child: Text("Rename")))
                    items.append(Chrome.gap(8))
                    items.append(Button(onPressed: { [weak self] in self?.setState { self?._confirmDelete = true } }, child: Text("Delete")))
                    items.append(Chrome.gap(8))
                    items.append(Button(onPressed: { [weak self] in self?._movePage(by: -1) }, child: Text("Move up")))
                    items.append(Chrome.gap(4))
                    items.append(Button(onPressed: { [weak self] in self?._movePage(by: 1) }, child: Text("Move down")))
                    items.append(Chrome.gap(8))
                    items.append(Button(onPressed: _slug == _manifest?.home ? nil : { [weak self] in
                        guard let self, let slug = self._slug, let home = self._manifest?.home else { return }
                        self.setState { self._confirmHome = (slug, home) }
                    }, child: Text(_slug == _manifest?.home ? "Home page" : "Make home page…")))
                    items.append(Chrome.gap(8))
                }
                items.append(Button(onPressed: { [weak self] in self?._openPublish() }, child: Text("Publish…")))
                items.append(Chrome.gap(8))
                items.append(FilledButton(onPressed: { [weak self] in self?._beginEdit() }, child: Text("Edit document")))
            }
        }
        var heading: [Widget] = [
            Text(_manifest?.title ?? "Site", style: WikiAppearance.text(13, bold: true, color: WikiAppearance.blue)),
            Chrome.vgap(8), Text(title, style: WikiAppearance.text(_compact ? 25 : 32, bold: true)),
        ]
        let identity = [_manifest?.details?.byline, _manifest?.details?.edition].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        if !identity.isEmpty { heading += [Chrome.vgap(8), Text(identity, style: WikiAppearance.text(14, color: WikiAppearance.muted))] }
        if store.canEdit {
            heading += [Chrome.vgap(12), Text(_publicationStatus, style: WikiAppearance.text(14, color: WikiAppearance.muted))]
            #if !os(WASI)
            if let slug = _slug, _isUnpublished(slug) {
                heading += [Chrome.vgap(8), Text("Unpublished chapter — its title and document stay on this device until you include it in publication review.", style: WikiAppearance.text(14, bold: true))]
            } else if _heldDraft {
                heading += [Chrome.vgap(8), Text("Separate local draft — publishing keeps the previously uploaded document until you include this draft in publication review.", style: WikiAppearance.text(14, bold: true))]
            }
            #endif
        }
        heading += _websiteControls()
        heading += _publishFeedback()
        if _publishOpen {
            heading += [Chrome.vgap(12), Text("Publish the included pages and their Word and PDF downloads. Unpublished chapters and held draft edits stay local. After publishing, check the live website before sharing its link.", style: WikiAppearance.text(14, color: WikiAppearance.muted))]
        }
        if !items.isEmpty { heading += [Chrome.vgap(18), Wrap(spacing: 0, runSpacing: 8, children: items)] }
        return DecoratedBox(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: WikiAppearance.line, width: 1))),
            child: Padding(padding: EdgeInsets(all: _compact ? 16 : 24), child:
                Column(crossAxisAlignment: .stretch, children: heading)))
    }

    private func _reader(viewWidth: Double) -> Widget {
        let page = Color(0xFFFFFFFF)
        let theme = _theme
        theme.textColor = Color(0xFF1B1B1B)
        theme.caretColor = theme.textColor
        theme.selectionColor = WikiAppearance.blue.withOpacity(0.20)
        let paged = showPages ? _pageSetup : nil
        // A page wider than the room it has is shown smaller, whole.
        var zoom = 1.0
        if let setup = paged {
            let room = viewWidth - (_compact ? 24 : 288 + 48) - (_tocOpen && !_compact ? 260 : 0) - 48
            let pageWidth = setup.width * theme.pixelsPerPoint
            if pageWidth > room, room > 200 { zoom = max(0.4, room / pageWidth) }
        }
        return RichEditable(
            controller: _controller, theme: theme,
            padding: paged != nil ? EdgeInsets(all: 24) : EdgeInsets(left: _compact ? 20 : 40, top: 28, right: _compact ? 20 : 40, bottom: 120),
            autofocus: false, backgroundColor: paged != nil ? WikiAppearance.paper : page, zoom: zoom,
            pageSetup: paged, pageColor: page,
            onPageInfo: { [weak self] p, n in
                guard let self, self._pageInfo != (p, n) else { return }
                self.setState { self._pageInfo = (p, n) }
            },
            onShortcut: { [weak self] key, mods in self?._shortcut(key, mods) ?? false },
            onLinkActivate: { [weak self] link in self?._followLink(link) })
    }

    /// The headings, with page numbers in page view; a click scrolls there.
    private func _contents(_ fluent: FluentThemeData) -> Widget {
        let toc = _toc
        let caret = _controller.caret.paragraph
        let current = toc.lastIndex { $0.index <= caret }
        let list = ListView(key: ValueKey("toc-\(_slug ?? "")-\(toc.count)-\(current ?? -1)"), itemCount: toc.count) { [weak self] _, i in
            let h = toc[i]
            var row: [Widget] = [Expanded(child: Text(h.text, style: (i == current ? fluent.typography.bodyStrong : fluent.typography.body)?.copyWith(color: i == current ? WikiAppearance.blue : WikiAppearance.ink), softWrap: false, overflow: .ellipsis))]
            if let p = h.page, self?.showPages == true {
                row.append(Chrome.gap(8))
                row.append(Text("\(p)", style: fluent.typography.caption?.copyWith(color: WikiAppearance.muted)))
            }
            return Padding(padding: EdgeInsets(left: 8 + Double(max(0, h.level - 1)) * 12, top: 0, right: 8, bottom: 0), child: FlyoutListTile(
                onPressed: {
                    guard let self else { return }
                    self._controller.moveTo(RichPosition(paragraph: h.index, offset: 0), reveal: .top)
                    self.setState {}
                },
                text: Row(children: row),
                margin: EdgeInsets(left: 0, top: 0, right: 0, bottom: 1),
                selected: i == current))
        }
        return SizedBox(width: _compact ? nil : 260, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(border: Border(left: BorderSide(color: WikiAppearance.line, width: 1))),
            child: Column(crossAxisAlignment: .stretch, children: [
                Padding(padding: EdgeInsets(left: 16, top: 14, right: 16, bottom: 8), child: Text("Contents", style: WikiAppearance.text(13, bold: true, color: WikiAppearance.blue))),
                Expanded(child: list),
            ])))
    }

    /// A link inside a page: one of this site's routes opens in place;
    /// anything else opens outside — a new tab, or the system's browser.
    private func _followLink(_ link: String) {
        if let m = _manifest, link.hasPrefix("/") || link.hasPrefix(m.base) {
            let slug = SiteFiles.slug(ofRoute: link, base: m.base)
            if m.node(slug) != nil {
                _pendingParagraph = Self.paragraph(inRoute: link)
                _load(slug, push: true)
                return
            }
        }
        if let open = hostOpenURL { open(link) } else { setState { _status = link } }
    }

    private func _statusBar(_ fluent: FluentThemeData) -> Widget {
        var parts: [String] = []
        if showPages { parts.append("Page \(_pageInfo.page) of \(_pageInfo.count)") }
        if let s = _status { parts.append(s) }
        else if store.canEdit { parts.append("Local draft preview — edit and review here, then publish when ready.") }
        return DecoratedBox(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: WikiAppearance.line, width: 1))),
            child: Padding(padding: EdgeInsets(left: 20, top: 10, right: 20, bottom: 10),
                           child: Text(parts.joined(separator: " · "), style: fluent.typography.caption?.copyWith(color: WikiAppearance.muted), softWrap: false, overflow: .ellipsis)))
    }
}
