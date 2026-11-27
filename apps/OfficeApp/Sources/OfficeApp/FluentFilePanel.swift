// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A Fluent-styled open/save panel, in-process, over Foundation's
// FileManager. The SDK's MacosFilePanel is the same idea in the other
// style; a native NSOpenPanel per host is a later host-injection closure.

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

enum FilePanelMode {
    case open
    case save
    case folder
}

final class FluentFilePanel: StatefulWidget {
    let mode: FilePanelMode
    let initialDirectory: String
    let suggestedName: String
    let extensions: [String]
    /// A browser tab's Save As, where the browser picks the folder (a download): only a name, a format and a
    /// Download button, no folders. The name handed back is a bare file name.
    let namesOnly: Bool
    let onDone: (String?) -> Void

    init(mode: FilePanelMode, initialDirectory: String, suggestedName: String = "",
         extensions: [String], namesOnly: Bool = false, onDone: @escaping (String?) -> Void) {
        self.mode = mode
        self.initialDirectory = initialDirectory
        self.suggestedName = suggestedName
        self.extensions = extensions
        self.namesOnly = namesOnly
        self.onDone = onDone
        super.init()
    }

    override func createState() -> State<StatefulWidget> { FluentFilePanelState() }
}

private struct Entry {
    let name: String
    let path: String
    let isDirectory: Bool
}

final class FluentFilePanelState: State<StatefulWidget> {
    private var _dir = ""
    private var _entries: [Entry] = []
    private var _selected: String? = nil
    private let _name = TextEditingController()
    private var _lastClickAt = 0.0
    private var _lastClickPath = ""
    /// The format picked in a names-only panel (an extension of `extensions`).
    private var _format = ""

    private var _w: FluentFilePanel { widget as! FluentFilePanel }

    override func initState() {
        super.initState()
        _name.text = _w.suggestedName
        // (The name is ready to be typed over, as in any save panel: the
        // field has the keys and the name without its extension is
        // selected. ⌘S on an untitled document used to open the panel
        // with nothing focused, and a typed name went nowhere.)
        let name = _w.suggestedName
        let stem = name.lastIndex(of: ".").map { name[..<$0].utf16.count } ?? name.utf16.count
        _name.selection = TextSelection(baseOffset: 0, extentOffset: stem > 0 ? stem : name.utf16.count)
        let ext = name.pathExtension.lowercased()
        _format = _w.extensions.contains(ext) ? ext : _w.extensions.first ?? ""
        if _w.namesOnly { return }
        _load(_w.initialDirectory)
    }

    override func dispose() {
        _name.dispose()
        super.dispose()
    }

    private func _load(_ dir: String) {
        let fm = FileManager.default
        #if os(WASI)
        return  // no directories to list in a tab
        #else
        var isDir: ObjCBool = false
        let dir = dir.portablePath
        guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return }
        let names = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        var entries: [Entry] = []
        for name in names where !name.hasPrefix(".") {
            let path = dir.appendingPathComponent(name)
            var d: ObjCBool = false
            fm.fileExists(atPath: path, isDirectory: &d)
            let ext = name.pathExtension.lowercased()
            if !d.boolValue && _w.mode == .folder { continue }
            if !d.boolValue && !_w.extensions.isEmpty && !_w.extensions.contains(ext) { continue }
            entries.append(Entry(name: name, path: path, isDirectory: d.boolValue))
        }
        entries.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.lowercased() < b.name.lowercased()
        }
        _dir = dir
        _entries = entries
        _selected = nil
        setState {}
        #endif
    }

    private func _confirm() {
        switch _w.mode {
        case .folder:
            _w.onDone(_dir)
        case .open:
            if let s = _selected { _w.onDone(s) }
        case .save:
            var name = _name.text.trimmingWhitespace(newlines: false).portablePath
            // The box opens with the stem selected, so a name typed WITH
            // its extension lands in front of the one already there:
            // "report.docx.docx" was meant as "report.docx".
            let ext = name.pathExtension
            if !ext.isEmpty, name.deletingPathExtension.pathExtension.lowercased() == ext.lowercased() {
                name = name.deletingPathExtension
            }
            guard !name.isEmpty else { return }
            if _w.namesOnly {
                // A name, never a path; its extension, when it is one of the formats, wins over the picked one.
                name = name.lastPathComponent
                if !_w.extensions.contains(name.pathExtension.lowercased()) { name += ".\(_format)" }
                _w.onDone(name)
                return
            }
            // A whole path typed in the box is taken as one, not as a name
            // inside the listed folder; a folder typed there is gone to.
            var target = name.isAbsolutePath ? name : _dir.appendingPathComponent(name)
            #if !os(WASI)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: target, isDirectory: &isDir), isDir.boolValue {
                _name.text = _w.suggestedName
                _load(target)
                return
            }
            #endif
            if name.pathExtension.isEmpty, let ext = _w.extensions.first { target += ".\(ext)"; name += ".\(ext)" }
            _w.onDone(target)
        }
    }

    private func _activate(_ e: Entry) {
        if e.isDirectory {
            _load(e.path)
        } else {
            _selected = e.path
            if _w.mode == .save { _name.text = e.name }
            let now = Date().timeIntervalSince1970
            let double = now - _lastClickAt < 0.45 && _lastClickPath == e.path
            _lastClickAt = now
            _lastClickPath = e.path
            if double { _confirm() } else { setState {} }
        }
    }

    private static let formatNames = ["docx": "Word Document", "rtf": "Rich Text", "md": "Markdown",
                                      "txt": "Plain Text", "pptx": "PowerPoint", "xlsx": "Excel Workbook",
                                      "csv": "CSV", "tsv": "Tab-separated text"]

    /// The format buttons: a pick sets the extension of the name in the box too.
    private func _pickFormat(_ ext: String) {
        var name = _name.text
        if _w.extensions.contains(name.pathExtension.lowercased()) { name = name.deletingPathExtension }
        _name.text = name + "." + ext
        setState { _format = ext }
    }

    private func _namesOnly(_ fluent: FluentThemeData) -> Widget {
        var formats: [Widget] = [SizedBox(width: 140, height: nil, child: Text("Format:", style: fluent.typography.body))]
        for ext in _w.extensions {
            let label = Text("\(Self.formatNames[ext] ?? ext.uppercased()) (.\(ext))")
            formats.append(ext == _format
                           ? FilledButton(onPressed: {}, child: label)
                           : Button(onPressed: { [weak self] in self?._pickFormat(ext) }, child: label))
            formats.append(Chrome.gap(8))
        }
        return Column(crossAxisAlignment: .stretch, children: [
            Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 140, height: nil, child: Text("File name:", style: fluent.typography.body)),
                Expanded(child: FluentTextBox(controller: _name, onSubmitted: { [weak self] _ in self?._confirm() },
                                              autofocus: true)),
            ]),
            Chrome.vgap(12),
            Row(crossAxisAlignment: .center, children: formats),
            Chrome.vgap(12),
            Text("Your browser saves the copy where it keeps downloads.", style: fluent.typography.caption),
            Chrome.vgap(12),
            Row(crossAxisAlignment: .center, children: [
                Expanded(child: SizedBox(width: 0, height: 0, child: nil)),
                Button(onPressed: { [weak self] in self?._w.onDone(nil) }, child: Text("Cancel")),
                Chrome.gap(8),
                FilledButton(onPressed: { [weak self] in self?._confirm() }, child: Text("Download")),
            ]),
        ])
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        if _w.namesOnly { return _namesOnly(fluent) }
        let places: [(String, String)] = [
            ("Home", homeDirectory()),
            ("Desktop", homeDirectory() + "/Desktop"),
            ("Documents", homeDirectory() + "/Documents"),
            ("Downloads", homeDirectory() + "/Downloads"),
        ]
        let sidebar = Column(crossAxisAlignment: .stretch, children: places.map { name, path in
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 2),
                    child: FlyoutListTile(onPressed: { [weak self] in self?._load(path) },
                                          icon: Icon(FluentSystemIcons.folderOpen, size: 16,
                                                     color: fluent.resources.textFillColorPrimary),
                                          text: Text(name), selected: path == _dir))
        })

        let crumbs = Row(crossAxisAlignment: .center, children: [
            Chrome.icon(FluentSystemIcons.up, "Up", fluent) { [weak self] in
                guard let self else { return }
                // "C:/Users" goes up to "C:/", and "C:/" is the top.
                var parent = self._dir.deletingLastPathComponent
                if parent.hasSuffix(":") { parent += "/" }
                if !parent.isEmpty, parent != self._dir { self._load(parent) }
            },
            Chrome.gap(6),
            Expanded(child: Text(_dir.displayPath, style: fluent.typography.caption)),
        ])

        let list = ListView(itemCount: _entries.count) { [weak self] _, i in
            guard let self, i < self._entries.count else { return SizedBox(width: 0, height: 0, child: nil) }
            let e = self._entries[i]
            return FlyoutListTile(
                onPressed: { [weak self] in self?._activate(e) },
                icon: Icon(e.isDirectory ? FluentSystemIcons.folderOpen : FluentSystemIcons.document,
                           size: 16, color: fluent.resources.textFillColorPrimary),
                text: Text(e.name),
                margin: EdgeInsets(left: 0, top: 0, right: 0, bottom: 1),
                selected: e.path == self._selected)
        }

        var bottom: [Widget] = []
        if _w.mode == .save {
            bottom.append(SizedBox(width: 140, height: nil, child: Text("File name:", style: fluent.typography.body)))
            bottom.append(Expanded(child: FluentTextBox(controller: _name, onSubmitted: { [weak self] _ in self?._confirm() }, autofocus: true)))
        } else {
            bottom.append(Expanded(child: Text(_w.mode == .folder ? "Choose this folder, or open a subfolder." : (_selected.map { $0.lastPathComponent } ?? ""),
                                               style: fluent.typography.body)))
        }
        bottom.append(Chrome.gap(12))
        bottom.append(Button(onPressed: { [weak self] in self?._w.onDone(nil) }, child: Text("Cancel")))
        bottom.append(Chrome.gap(8))
        let canConfirm = _w.mode != .open || _selected != nil
        bottom.append(FilledButton(onPressed: canConfirm ? { [weak self] in self?._confirm() } : nil,
                                   child: Text(_w.mode == .folder ? "Choose folder" : (_w.mode == .save ? "Save" : "Open"))))

        return Column(crossAxisAlignment: .stretch, children: [
            crumbs,
            Chrome.vgap(8),
            Expanded(child: Row(crossAxisAlignment: .stretch, children: [
                SizedBox(width: 160, height: nil, child: sidebar),
                Chrome.gap(12),
                Expanded(child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: fluent.resources.cardBackgroundFillColorDefault,
                        border: Border.all(color: fluent.resources.cardStrokeColorDefault, width: 1),
                        borderRadius: BorderRadius.all(Radius(circular: 4))),
                    child: Padding(padding: EdgeInsets(left: 4, top: 4, right: 4, bottom: 4), child: list))),
            ])),
            Chrome.vgap(12),
            Row(crossAxisAlignment: .center, children: bottom),
        ])
    }
}
