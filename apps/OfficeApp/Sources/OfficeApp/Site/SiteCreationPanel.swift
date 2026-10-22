// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Flutter

#if !os(WASI)
final class SiteCreationPanel: StatefulWidget {
    let onCreated: (String, Bool) -> Void
    let onCancel: () -> Void

    init(onCreated: @escaping (String, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.onCreated = onCreated
        self.onCancel = onCancel
        super.init()
    }

    override func createState() -> State<StatefulWidget> { _SiteCreationState() }
}

private final class _SiteCreationState: State<StatefulWidget> {
    private let _title = TextEditingController()
    private var _parent = ""
    private var _choosingFolder = false
    private var _choosingSource = false
    private var _chosen = false
    private var _source: String?
    private var _error: String?
    private var _creating = false
    private var _w: SiteCreationPanel { widget as! SiteCreationPanel }

    override func initState() {
        super.initState()
        let documents = homeDirectory() + "/Documents"
        _parent = FileManager.default.fileExists(atPath: documents) ? documents : homeDirectory()
    }

    override func dispose() { _title.dispose(); super.dispose() }

    private func _create() {
        guard !_creating else { return }
        let title = _title.text, parent = _parent, source = _source
        setState { _creating = true; _error = nil }
        let worker = Thread { [weak self] in
            let result = Result { try SiteCreation.create(title: title, parent: parent, source: source) }
            DispatchQueue.main.async {
                guard let self, self.mounted else { return }
                switch result {
                case .success(let path): self._w.onCreated(path, source == nil)
                case .failure(let error): self.setState { self._creating = false; self._error = "\(error)" }
                }
            }
        }
        // Word decoding needs more stack than a Dispatch worker provides
        // in debug builds. Keep it off the UI thread with a main-sized stack.
        worker.name = "Open publication manuscript"
        worker.stackSize = 8 * 1024 * 1024
        worker.start()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        if _choosingSource {
            return Column(crossAxisAlignment: .stretch, children: [
                Text("Choose your Word document", style: fluent.typography.title), Chrome.vgap(12),
                Text("We'll create a publication copy. Your original file stays unchanged.", style: fluent.typography.body), Chrome.vgap(16),
                Expanded(child: FluentFilePanel(mode: .open, initialDirectory: _source?.deletingLastPathComponent ?? _parent, extensions: ["docx"], onDone: { [weak self] path in
                    guard let self else { return }
                    self.setState {
                        if let path {
                            if self._title.text.trimmingWhitespace().isEmpty || self._title.text == self._source?.lastPathComponent.deletingPathExtension {
                                self._title.text = path.lastPathComponent.deletingPathExtension
                            }
                            self._source = path
                            self._chosen = true
                            self._error = nil
                        }
                        self._choosingSource = false
                    }
                })),
            ])
        }
        if _choosingFolder {
            return Column(crossAxisAlignment: .stretch, children: [
                Text("Choose a location", style: fluent.typography.title), Chrome.vgap(16),
                Expanded(child: FluentFilePanel(mode: .folder, initialDirectory: _parent, extensions: [], onDone: { [weak self] path in
                    guard let self else { return }
                    self.setState { if let path { self._parent = path }; self._choosingFolder = false }
                })),
            ])
        }
        let destination = _parent.appendingPathComponent(SiteFiles.slug(for: _title.text.trimmingWhitespace()))
        var rows: [Widget] = [
            Text("What would you like to publish?", style: fluent.typography.title), Chrome.vgap(12),
            Text("Bring a report, handbook or manuscript from Word, or start a new document here.", style: fluent.typography.body),
            Chrome.vgap(24), Wrap(spacing: 12, runSpacing: 8, children: [
                FilledButton(onPressed: _creating ? nil : { [weak self] in self?.setState { self?._choosingSource = true } }, child: Text(_source == nil ? "Choose a Word document…" : "Choose a different document…")),
                Button(onPressed: _creating ? nil : { [weak self] in
                    self?.setState { self?._chosen = true; self?._source = nil; self?._error = nil }
                }, child: Text("Start blank")),
            ]),
        ]
        if _chosen {
            rows += [Chrome.vgap(20),
                Text(_source.map { "Publication copy of " + $0.lastPathComponent } ?? "A new document", style: fluent.typography.bodyStrong),
                Chrome.vgap(8), Text(_source == nil ? "Start writing in a blank document. Save, then choose Back to preview to review it as a reader." : "Next you'll see your document as a reader would. Check the layout, edit it, or add more pages. Your original Word file stays unchanged.", style: fluent.typography.body),
                Chrome.vgap(20), Text("Publication title", style: fluent.typography.bodyStrong), Chrome.vgap(8),
                FluentTextBox(controller: _title, placeholderText: "e.g. Product handbook", onChanged: { [weak self] _ in self?.setState {} }, autofocus: true),
                Chrome.vgap(16), Text("Local copy: " + destination, style: fluent.typography.caption), Chrome.vgap(8),
                Button(onPressed: _creating ? nil : { [weak self] in self?.setState { self?._choosingFolder = true } }, child: Text("Change save location…")),
                Chrome.vgap(20), Text("Nothing is uploaded yet. Review and edit your draft, then choose Publish when you're ready to share it.", style: fluent.typography.body),
            ]
        }
        if let error = _error { rows += [Chrome.vgap(16), Text(error, style: fluent.typography.body)] }
        rows += [Chrome.vgap(24), Row(children: [
            FilledButton(onPressed: _creating || !_chosen || _title.text.trimmingWhitespace().isEmpty ? nil : { [weak self] in self?._create() }, child: Text(_creating ? "Opening draft…" : (_chosen && _source == nil ? "Start writing" : "Open draft"))),
            Chrome.gap(12), Button(onPressed: _creating ? nil : _w.onCancel, child: Text("Cancel")),
        ])]
        return SingleChildScrollView(child: Column(crossAxisAlignment: .start, children: rows))
    }
}
#endif
