// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Flutter

#if !os(WASI)
final class SiteHostingPanel: StatefulWidget {
    let store: LocalSiteStore
    let onClose: () -> Void
    init(store: LocalSiteStore, onClose: @escaping () -> Void) {
        self.store = store; self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { _SiteHostingState() }
}

private final class _SiteHostingState: State<StatefulWidget> {
    private var _w: SiteHostingPanel { widget as! SiteHostingPanel }
    private let _title = TextEditingController()
    private let _repository = TextEditingController()
    private let _url = TextEditingController()
    private let _author = TextEditingController()
    private let _email = TextEditingController()
    private var _identity: SitePublishingIdentity.Snapshot?
    private var _pagesSource: String?
    private var _snapshot: SiteHosting.Snapshot?
    private var _busy = false
    private var _notice: String?
    private var _problems: [String] = []

    override func initState() {
        super.initState()
        do {
            let saved = try SiteHosting.load(repo: _w.store.repo)
            _snapshot = saved
            _title.text = saved.config.title
            _repository.text = saved.config.repository ?? ""
            _url.text = saved.config.url ?? ""
            _run(refreshIdentity: true) { }
        } catch { _notice = "Could not read settings: \(error)" }
    }

    override func dispose() {
        _title.dispose(); _repository.dispose(); _url.dispose(); _author.dispose(); _email.dispose()
        super.dispose()
    }

    /// Git checks stay off the UI thread. Results always describe the saved
    /// settings; editing a field does not configure a remote or contact GitHub.
    private func _run(success: String? = nil, refreshIdentity: Bool = false, action: @escaping () throws -> Void) {
        guard !_busy else { return }
        let repo = _w.store.repo, web = _w.store.webStage, out = _w.store.out
        setState { _busy = true; _notice = nil }
        DispatchQueue.global().async { [weak self] in
            let result = Result { try action() }
            let problems = SiteHosting.readiness(repo: repo, web: web)
            let identity = refreshIdentity ? try? SitePublishingIdentity.load(repo: repo) : nil
            let source: String
            do { source = try SiteHosting.pagesSource(repo: repo, out: out) }
            catch { source = "\(error)" }
            DispatchQueue.main.async {
                guard let self, self.mounted else { return }
                self.setState {
                    self._busy = false
                    self._problems = problems
                    self._pagesSource = source
                    if case .success = result, let identity {
                        self._identity = identity
                        self._author.text = identity.name
                        self._email.text = identity.email
                    }
                    switch result {
                    case .success: self._notice = success
                    case .failure(let error): self._notice = "\(error)"
                    }
                }
            }
        }
    }

    private func _save() {
        guard let snapshot = _snapshot else { return }
        do {
            let address = _url.text.trimmingWhitespace().isEmpty
                ? try SiteHosting.suggestedURL(repository: _repository.text) : _url.text
            let settings = try SiteHosting.Settings(title: _title.text, repository: _repository.text, url: address)
            // Saving one small local JSON file is atomic. Refresh the snapshot
            // only after our write succeeds, never after a stale-save rejection.
            try SiteHosting.save(settings, repo: _w.store.repo, expected: snapshot)
            _snapshot = try SiteHosting.load(repo: _w.store.repo)
            _title.text = settings.title
            _repository.text = settings.repository ?? ""
            _url.text = settings.url ?? ""
            let repo = _w.store.repo
            _run(success: "Website details saved and connected locally. Nothing has been uploaded.") { try SiteHosting.connect(repo: repo) }
        } catch { setState { _notice = "\(error)" } }
    }

    private var _edited: Bool {
        guard let config = _snapshot?.config else { return true }
        return _title.text != config.title || _repository.text != (config.repository ?? "") || _url.text != (config.url ?? "")
    }

    private var _authorEdited: Bool {
        guard let identity = _identity else { return false }
        return _author.text != identity.name || _email.text != identity.email
    }

    private func _saveAuthor() {
        guard let expected = _identity else { return }
        let name = _author.text, email = _email.text, repo = _w.store.repo
        _run(success: "Author saved for this publication. Your other projects are unchanged.", refreshIdentity: true) {
            try SitePublishingIdentity.save(name: name, email: email, repo: repo, expected: expected)
        }
    }

    private func _link(_ title: String, _ url: String, enabled: Bool = true) -> Widget {
        Button(onPressed: _busy || !enabled ? nil : { hostOpenURL?(url) }, child: Text(title))
    }

    override func build(_ context: any BuildContext) -> Widget {
        let edited = _edited || _authorEdited
        let pagesURL = _snapshot?.config.repository.flatMap { try? SiteHosting.pagesSettingsURL(repository: $0) }
        var rows: [Widget] = [
            Text("Publish your writing", style: WikiAppearance.text(30, bold: true)), Chrome.vgap(10),
            Text("Set up your website once. After that, edit, preview and publish to the same address.", style: WikiAppearance.text()),
            Chrome.vgap(16), Button(onPressed: _busy ? nil : _w.onClose, child: Text(edited ? "Back without saving changes" : "Back to publication")),
        ]
        if let notice = _notice { rows += [Chrome.vgap(16), Text(notice, style: WikiAppearance.text(15, bold: true))] }
        rows += [
            Chrome.vgap(24), Text("1. Choose a home for your publication", style: WikiAppearance.text(22, bold: true)), Chrome.vgap(8),
            Text("GitHub stores your publication and hosts its website. Create an empty repository, then paste its address below. Your upload includes source documents and the website's Word and PDF downloads.", style: WikiAppearance.text()),
            Chrome.vgap(10), _link("Create a repository on GitHub", "https://github.com/new"),
            Chrome.vgap(18), Text("Publication title", style: WikiAppearance.text(15, bold: true)), Chrome.vgap(8),
            _field(_title, "Product handbook"),
            Chrome.vgap(16), Text("Repository address", style: WikiAppearance.text(15, bold: true)), Chrome.vgap(8),
            _field(_repository, "https://github.com/owner/handbook"),
            Chrome.vgap(16), Text("Website address (optional)", style: WikiAppearance.text(15, bold: true)), Chrome.vgap(8),
            _field(_url, "Leave blank to use your GitHub Pages address"), Chrome.vgap(8),
            Text("Already have a website address? Enter it here. Otherwise we fill it from your repository when you save.", style: WikiAppearance.text(14, color: WikiAppearance.muted)),
            Chrome.vgap(10), Wrap(spacing: 12, runSpacing: 8, children: [
                FilledButton(onPressed: _busy || _snapshot == nil ? nil : { [weak self] in self?._save() }, child: Text("Save and connect")),
                Button(onPressed: _busy ? nil : { [weak self] in
                    guard let self else { return }
                    do { self._url.text = try SiteHosting.suggestedURL(repository: self._repository.text); self.setState {} }
                    catch { self.setState { self._notice = "\(error)" } }
                }, child: Text("Use GitHub Pages address")),
            ]),
            Chrome.vgap(26), Text("2. Set your publishing name", style: WikiAppearance.text(22, bold: true)), Chrome.vgap(8),
            Text("Your name and email appear in the publication's change history. Use your GitHub no-reply email if you prefer to keep your personal email private. These settings apply only to this publication.", style: WikiAppearance.text()),
            Chrome.vgap(14), Text("Author name", style: WikiAppearance.text(15, bold: true)), Chrome.vgap(8),
            _field(_author, "Your name"),
            Chrome.vgap(14), Text("Publishing email", style: WikiAppearance.text(15, bold: true)), Chrome.vgap(8),
            _field(_email, "Your GitHub email or no-reply address"), Chrome.vgap(10),
            Wrap(spacing: 12, runSpacing: 8, children: [
                FilledButton(onPressed: _busy || _identity == nil ? nil : { [weak self] in self?._saveAuthor() }, child: Text("Save author")),
                _link("Find my GitHub no-reply email", "https://github.com/settings/emails"),
                _link("GitHub sign-in help", "https://docs.github.com/en/get-started/git-basics/caching-your-github-credentials-in-git"),
            ]), Chrome.vgap(8),
            Text("Saving your author name does not sign you in. Uploads use the Git credentials already configured on this computer.", style: WikiAppearance.text(14, color: WikiAppearance.muted)),
            Chrome.vgap(26), Text("3. Publish and turn on your website", style: WikiAppearance.text(22, bold: true)), Chrome.vgap(8),
            Text("Return to the preview and Publish. Then open your repository's website settings to enable GitHub Pages.", style: WikiAppearance.text()),
            Chrome.vgap(8), Text(_pagesSource ?? "Checking the publication's website settings…", style: WikiAppearance.text()),
            Chrome.vgap(10), Wrap(spacing: 12, runSpacing: 8, children: [
                _link("Open website settings on GitHub", pagesURL ?? "https://github.com", enabled: pagesURL != nil && !_edited),
                _link("Website setup guide", "https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site"),
            ]), Chrome.vgap(10),
            Text("Once hosting finishes, choose Check live website in the preview. Confirm the uploaded version, review the website, then copy its link for readers.", style: WikiAppearance.text()),
            Chrome.vgap(24), Text(_busy ? "Checking saved setup…" : "Before you publish", style: WikiAppearance.text(22, bold: true)), Chrome.vgap(10),
        ]
        if !_busy {
            if _problems.isEmpty && _snapshot != nil {
                rows.append(Text("Local setup is ready. Your GitHub sign-in and website deployment are checked when you upload and check the live website.", style: WikiAppearance.text()))
            } else { for problem in _problems { rows += [Text("• " + problem, style: WikiAppearance.text()), Chrome.vgap(8)] } }
        }
        if edited { rows += [Chrome.vgap(10), Text("Save your changed website details or author before continuing. Back discards unsaved form changes.", style: WikiAppearance.text(14, color: WikiAppearance.muted))] }
        rows += [Chrome.vgap(18), Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton(onPressed: _busy || edited || !_problems.isEmpty || _snapshot == nil ? nil : _w.onClose, child: Text("Continue to publish")),
            Button(onPressed: _busy ? nil : { [weak self] in self?._run { } }, child: Text("Check saved setup")),
        ])]
        return ColoredBox(color: WikiAppearance.paper, child: Padding(padding: EdgeInsets(all: 28), child:
            SingleChildScrollView(child: Column(crossAxisAlignment: .stretch, children: rows))))
    }

    private func _field(_ controller: TextEditingController, _ placeholder: String) -> Widget {
        // Disable edits while checks/connection run, so their result refers to
        // exactly the values the author saved.
        FluentTextBox(controller: controller, placeholderText: placeholder,
                      onChanged: { [weak self] _ in self?.setState {} }, enabled: !_busy, style: WikiAppearance.text(17),
                      tabGroup: "publication-hosting", tabOrder: controller === _title ? 0 : controller === _repository ? 1 : controller === _url ? 2 : controller === _author ? 3 : 4)
    }
}
#endif
