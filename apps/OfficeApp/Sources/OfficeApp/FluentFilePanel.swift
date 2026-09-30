// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A Fluent-styled open/save panel, in-process, over Foundation's
// FileManager. The SDK's MacosFilePanel is the same idea in the other
// style; a native NSOpenPanel per host is a later host-injection closure.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

enum FilePanelMode {
    case open
    case save
}

final class FluentFilePanel: StatefulWidget {
    let mode: FilePanelMode
    let initialDirectory: String
    let suggestedName: String
    let extensions: [String]
    let onDone: (String?) -> Void

    init(mode: FilePanelMode, initialDirectory: String, suggestedName: String = "",
         extensions: [String], onDone: @escaping (String?) -> Void) {
        self.mode = mode
        self.initialDirectory = initialDirectory
        self.suggestedName = suggestedName
        self.extensions = extensions
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

    private var _w: FluentFilePanel { widget as! FluentFilePanel }

    override func initState() {
        super.initState()
        _name.text = _w.suggestedName
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
        guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return }
        let names = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        var entries: [Entry] = []
        for name in names where !name.hasPrefix(".") {
            let path = dir.appendingPathComponent(name)
            var d: ObjCBool = false
            fm.fileExists(atPath: path, isDirectory: &d)
            let ext = name.pathExtension.lowercased()
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
        case .open:
            if let s = _selected { _w.onDone(s) }
        case .save:
            var name = _name.text.trimmingWhitespace(newlines: false)
            guard !name.isEmpty else { return }
            if name.pathExtension.isEmpty, let ext = _w.extensions.first { name += ".\(ext)" }
            _w.onDone(_dir.appendingPathComponent(name))
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

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
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
                let parent = self._dir.deletingLastPathComponent
                if !parent.isEmpty { self._load(parent) }
            },
            Chrome.gap(6),
            Expanded(child: Text(_dir, style: fluent.typography.caption)),
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
            bottom.append(Expanded(child: FluentTextBox(controller: _name, onSubmitted: { [weak self] _ in self?._confirm() })))
        } else {
            bottom.append(Expanded(child: Text(_selected.map { $0.lastPathComponent } ?? "",
                                               style: fluent.typography.body)))
        }
        bottom.append(Chrome.gap(12))
        bottom.append(Button(onPressed: { [weak self] in self?._w.onDone(nil) }, child: Text("Cancel")))
        bottom.append(Chrome.gap(8))
        let canConfirm = _w.mode == .save || _selected != nil
        bottom.append(FilledButton(onPressed: canConfirm ? { [weak self] in self?._confirm() } : nil,
                                   child: Text(_w.mode == .save ? "Save" : "Open")))

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
