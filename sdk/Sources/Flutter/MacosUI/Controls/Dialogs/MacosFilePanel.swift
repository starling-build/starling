// MacosFilePanel — the system open/save file dialog.
//
// One implementation shared by every consumer: apps embed it in-process as a
// modal overlay (MacosFilePanelOverlay), and the xdg portal picker renders it
// full-window (FileExplorerApp --picker), so the desktop shows a single
// file-dialog UI everywhere.

import FlutterSwiftBridge
import Foundation
#if os(Linux)
import Glibc
#endif

// MARK: - Options
//
// `MacosFilePanelOptions` is `FluentFilePanelOptions` (FluentUI/Controls/
// Dialogs/FluentFilePanel.swift): one options type, two faces. The Linux
// desktop shows the Fluent one; this stays for iOS.

// MARK: - Palette

/// Theme-keyed colors. Near-opaque surfaces so the dialog reads solid over
/// both the shell's glass and an app's own content; accents follow the
/// desktop's per-theme system blue.
private struct _PanelColors {
    let dark: Bool
    var surface: Color    { dark ? Color(0xF7262930) : Color(0xFAF5F5F7) }
    var sidebar: Color    { dark ? Color(0xFF20232A) : Color(0xFFEBEBEE) }
    var footer: Color     { dark ? Color(0xFF22252C) : Color(0xFFEFEFF2) }
    var hairline: Color   { dark ? Color(0x1FFFFFFF) : Color(0x1A000000) }
    var text: Color       { dark ? Color(0xFFE8E8E8) : Color(0xDD000000) }
    var secondary: Color  { dark ? Color(0x99FFFFFF) : Color(0x8C000000) }
    var tertiary: Color   { dark ? Color(0x66FFFFFF) : Color(0x66000000) }
    var disabled: Color   { dark ? Color(0x3AFFFFFF) : Color(0x33000000) }
    var rowAlt: Color     { dark ? Color(0x0AFFFFFF) : Color(0x08000000) }
    var hover: Color      { dark ? Color(0x14FFFFFF) : Color(0x0F000000) }
    var selection: Color  { dark ? Color(0x4D0A84FF) : Color(0x33007AFF) }
    var accent: Color     { dark ? Color(0xFF0A84FF) : Color(0xFF007AFF) }
    var accentText: Color { Color(0xFFFFFFFF) }
    var button: Color     { dark ? Color(0xFF3A3E46) : Color(0xFFE3E3E6) }
    var buttonText: Color { dark ? Color(0xFFDDDDDD) : Color(0xCC000000) }
    var fieldFill: Color  { dark ? Color(0x14FFFFFF) : Color(0x0F000000) }
}

// MARK: - Directory listing

/// One row of the panel's file list. Self-contained (the framework can't
/// reach app-side file helpers).
struct MacosFilePanelEntry {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64

    var fileExtension: String {
        isDirectory ? "" : (name as NSString).pathExtension.lowercased()
    }

    /// Emoji glyph — no icon-font dependency, usable before any font
    /// registration.
    var icon: String {
        if isDirectory { return "\u{1F4C1}" }
        switch fileExtension {
        case "swift", "c", "cc", "cpp", "h", "py", "js", "ts", "rs", "go",
             "java", "rb", "sh":
            return "\u{1F4DD}"
        case "png", "jpg", "jpeg", "gif", "bmp", "svg", "ico", "webp", "ppm":
            return "\u{1F5BC}"
        case "mp3", "wav", "flac", "aac", "ogg", "m4a":
            return "\u{1F3B5}"
        case "mp4", "mkv", "avi", "mov", "webm":
            return "\u{1F3AC}"
        case "zip", "tar", "gz", "bz2", "xz", "7z", "rar", "deb", "rpm":
            return "\u{1F4E6}"
        case "pdf":
            return "\u{1F4D1}"
        default:
            return "\u{1F4C4}"
        }
    }

    static func list(_ path: String, showHidden: Bool) -> [MacosFilePanelEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var out: [MacosFilePanelEntry] = []
        for name in names {
            if !showHidden && name.hasPrefix(".") { continue }
            let p = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &isDir) else { continue }
            let attrs = try? fm.attributesOfItem(atPath: p)
            let size = (attrs?[.size] as? UInt64) ?? 0
            out.append(MacosFilePanelEntry(
                name: name, path: p, isDirectory: isDir.boolValue, size: size))
        }
        out.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.lowercased() < b.name.lowercased()
        }
        return out
    }

    static func formatSize(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(bytes)
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(bytes) B" : String(format: "%.1f %@", v, units[i])
    }
}

// MARK: - MacosFilePanel

/// The dialog content: places sidebar, breadcrumb, file list, action bar
/// (+ filename field in save mode). Fills whatever box it is given — the
/// portal picker uses it as the whole window; in-app consumers wrap it in
/// MacosFilePanelOverlay.
public class MacosFilePanel: StatefulWidget {
    let options: MacosFilePanelOptions
    /// Selected absolute paths; empty means cancelled.
    let onComplete: ([String]) -> Void

    public init(options: MacosFilePanelOptions,
                onComplete: @escaping ([String]) -> Void) {
        self.options = options
        self.onComplete = onComplete
        super.init()
    }

    public override func createState() -> State<StatefulWidget> {
        return _MacosFilePanelState()
    }
}

class _MacosFilePanelState: State<StatefulWidget> {
    private var panel: MacosFilePanel { widget as! MacosFilePanel }
    private var options: MacosFilePanelOptions { panel.options }

    private var currentPath = ""
    private var history: [String] = []
    private var historyIndex = 0
    private var entries: [MacosFilePanelEntry] = []
    private var selected: Set<Int> = []
    private var showHidden = false
    // Manual double-click detection: a registered onDoubleTap holds the
    // gesture arena on the Linux DRM embedder (Foundation.Timer never
    // fires) and kills onTap — same workaround as the Files app.
    private var _lastClickTime = Date.distantPast
    private var _lastClickIndex: Int? = nil
    private let saveNameController = TextEditingController()

    private static var _home: String { realUserHomeDirectory() }

    private var places: [(name: String, icon: String, path: String)] {
        let home = Self._home
        return [
            ("Home", "\u{1F3E0}", home),
            ("Desktop", "\u{1F5A5}", home + "/Desktop"),
            ("Documents", "\u{1F4C4}", home + "/Documents"),
            ("Downloads", "\u{2B07}", home + "/Downloads"),
            ("Pictures", "\u{1F5BC}", home + "/Pictures"),
            ("Videos", "\u{1F3AC}", home + "/Videos"),
            ("Root", "\u{1F4C0}", "/"),
        ]
    }

    override func initState() {
        super.initState()
        var dir = options.initialDirectory ?? Self._home
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dir, isDirectory: &isDir)
            || !isDir.boolValue {
            dir = Self._home
        }
        if let name = options.suggestedName { saveNameController.text = name }
        history = [dir]
        _load(dir)
    }

    // MARK: Navigation

    private func _load(_ path: String) {
        currentPath = path
        entries = MacosFilePanelEntry.list(path, showHidden: showHidden)
        selected.removeAll()
    }

    private func _navigate(_ path: String) {
        if historyIndex < history.count - 1 {
            history = Array(history[0...historyIndex])
        }
        history.append(path)
        historyIndex = history.count - 1
        _load(path)
    }

    private var canGoBack: Bool { historyIndex > 0 }
    private var canGoUp: Bool { currentPath != "/" }

    // MARK: Selection semantics

    /// Whether a row can be part of the result (directories are always
    /// navigable but only selectable in directory mode).
    private func _selectable(_ entry: MacosFilePanelEntry) -> Bool {
        switch options.mode {
        case .directory:
            return entry.isDirectory
        case .save:
            // Selecting a file seeds the filename field.
            return !entry.isDirectory
        case .open:
            if entry.isDirectory { return false }
            guard let exts = options.allowedExtensions, !exts.isEmpty else { return true }
            return exts.contains(entry.fileExtension)
        }
    }

    private func _confirm() {
        switch options.mode {
        case .save:
            let name = saveNameController.text
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            panel.onComplete([(currentPath as NSString).appendingPathComponent(name)])
        case .directory:
            let paths = selected.sorted().map { entries[$0].path }
            panel.onComplete(paths.isEmpty ? [currentPath] : paths)
        case .open:
            let paths = selected.sorted().map { entries[$0].path }
            guard !paths.isEmpty else { return }
            panel.onComplete(paths)
        }
    }

    // MARK: Build

    override func build(_ context: any BuildContext) -> Widget {
        let dark = options.appearanceDark
            ?? (MacosTheme.of(context).brightness == .dark)
        let c = _PanelColors(dark: dark)
        return ColoredBox(
            color: c.surface,
            child: Column(children: [
                _header(c),
                _hairline(c),
                Expanded(child: Row(crossAxisAlignment: .stretch, children: [
                    SizedBox(width: 150, child: _sidebar(c)),
                    SizedBox(width: 1, child: ColoredBox(
                        color: c.hairline, child: SizedBox(expand: ()))),
                    Expanded(child: _fileList(c)),
                ])),
                _hairline(c),
                _actionBar(c),
            ])
        )
    }

    private func _hairline(_ c: _PanelColors) -> Widget {
        SizedBox(height: 1, child: ColoredBox(
            color: c.hairline, child: SizedBox(expand: ())))
    }

    private func _header(_ c: _PanelColors) -> Widget {
        // Breadcrumb: the last three path components (prefixed with an
        // ellipsis when truncated) — bounded width, no horizontal scrolling.
        var all: [(name: String, path: String)] = [("Root", "/")]
        var acc = ""
        for comp in currentPath.split(separator: "/") {
            acc += "/" + comp
            all.append((String(comp), acc))
        }
        var crumbs: [Widget] = []
        let shown = all.suffix(3)
        if all.count > 3 {
            crumbs.append(Text("\u{2026} \u{203A} ", style: TextStyle(
                color: c.tertiary, fontSize: 11)))
        }
        for (i, crumb) in shown.enumerated() {
            let isLast = i == shown.count - 1
            let target = crumb.path
            if i > 0 {
                crumbs.append(Text(" \u{203A} ", style: TextStyle(
                    color: c.tertiary, fontSize: 11)))
            }
            crumbs.append(GestureDetector(
                onTap: isLast ? nil : { [self] in setState { _navigate(target) } },
                child: Text(crumb.name, style: TextStyle(
                    color: isLast ? c.text : c.accent,
                    fontSize: 12,
                    fontWeight: isLast ? .w600 : .normal),
                    overflow: .ellipsis, maxLines: 1)
            ))
        }

        return Padding(
            padding: EdgeInsets(left: 10, top: 8, right: 10, bottom: 8),
            child: Row(children: [
                _headerButton("\u{2039}", enabled: canGoBack, c) { [self] in
                    guard canGoBack else { return }
                    setState { historyIndex -= 1; _load(history[historyIndex]) }
                },
                SizedBox(width: 2),
                _headerButton("^", enabled: canGoUp, c) { [self] in
                    guard canGoUp else { return }
                    setState { _navigate((currentPath as NSString).deletingLastPathComponent) }
                },
                SizedBox(width: 12),
                Expanded(child: ClipRect(child: Row(children: crumbs))),
                SizedBox(width: 12),
                // Hidden-files toggle: accent when on.
                GestureDetector(
                    onTap: { [self] in
                        setState {
                            showHidden = !showHidden
                            _load(currentPath)
                        }
                    },
                    behavior: .opaque,
                    child: Padding(
                        padding: EdgeInsets(left: 7, top: 3, right: 7, bottom: 3),
                        child: Text(".files", style: TextStyle(
                            color: showHidden ? c.accent : c.tertiary, fontSize: 11))
                    )
                ),
            ])
        )
    }

    private func _headerButton(_ glyph: String, enabled: Bool,
                               _ c: _PanelColors,
                               action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: enabled ? action : nil,
            behavior: .opaque,
            child: Padding(
                padding: EdgeInsets(left: 7, top: 3, right: 7, bottom: 3),
                child: Text(glyph, style: TextStyle(
                    color: enabled ? c.secondary : c.disabled, fontSize: 14))
            )
        )
    }

    private func _sidebar(_ c: _PanelColors) -> Widget {
        var items: [Widget] = [
            Padding(
                padding: EdgeInsets(left: 12, top: 10, bottom: 4),
                child: Text("PLACES", style: TextStyle(
                    color: c.tertiary, fontSize: 10, fontWeight: .w600))
            ),
        ]
        for place in places {
            let isActive = currentPath == place.path
            let p = place.path
            items.append(GestureDetector(
                onTap: { [self] in setState { _navigate(p) } },
                behavior: .opaque,
                child: ColoredBox(
                    color: isActive ? c.selection : Color(0x00000000),
                    child: Padding(
                        padding: EdgeInsets(left: 12, top: 6, right: 12, bottom: 6),
                        child: Text(place.name, style: TextStyle(
                            color: isActive ? c.text : c.secondary,
                            fontSize: 12))
                    )
                )
            ))
        }
        return ColoredBox(
            color: c.sidebar,
            child: Column(crossAxisAlignment: .stretch, children: items)
        )
    }

    private func _fileList(_ c: _PanelColors) -> Widget {
        if entries.isEmpty {
            return Center(child: Text("Empty folder", style: TextStyle(
                color: c.tertiary, fontSize: 13)))
        }

        var rows: [Widget] = []
        for (index, entry) in entries.enumerated() {
            let isSelected = selected.contains(index)
            let selectable = _selectable(entry)
            let idx = index
            let isDir = entry.isDirectory

            rows.append(GestureDetector(
                onTap: { [self] in
                    let now = Date()
                    let isDouble = _lastClickIndex == idx
                        && now.timeIntervalSince(_lastClickTime) < 0.4
                    _lastClickTime = now
                    _lastClickIndex = idx
                    if isDouble {
                        if isDir {
                            setState { _navigate(entry.path) }
                        } else if options.mode == .open && selectable {
                            selected = [idx]
                            _confirm()
                        }
                        return
                    }
                    setState {
                        if options.mode == .save && !isDir {
                            saveNameController.text = entry.name
                            selected = [idx]
                            return
                        }
                        guard selectable else { return }
                        if options.allowsMultiple {
                            if isSelected { selected.remove(idx) }
                            else { selected.insert(idx) }
                        } else {
                            selected = [idx]
                        }
                    }
                },
                child: ColoredBox(
                    color: isSelected ? c.selection
                         : (index % 2 == 0 ? Color(0x00000000) : c.rowAlt),
                    child: Padding(
                        padding: EdgeInsets(left: 12, top: 4, right: 12, bottom: 4),
                        child: Row(children: [
                            Expanded(child: Text(
                                isDir ? entry.name + "/" : entry.name,
                                style: TextStyle(
                                    color: isDir ? c.accent
                                         : (selectable ? c.text : c.disabled),
                                    fontSize: 12),
                                overflow: .ellipsis, maxLines: 1)),
                            SizedBox(width: 80, child: Text(
                                isDir ? "--" : MacosFilePanelEntry.formatSize(entry.size),
                                style: TextStyle(color: c.tertiary, fontSize: 11))),
                        ])
                    )
                )
            ))
        }

        // SingleChildScrollView + Column (not ListView): the proven scroll
        // path for DMA-BUF children — see the Files/Settings apps.
        return SingleChildScrollView(
            child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .stretch,
                children: rows)
        )
    }

    private func _actionBar(_ c: _PanelColors) -> Widget {
        var children: [Widget] = []

        if options.mode == .save {
            children.append(Text("Name:", style: TextStyle(
                color: c.secondary, fontSize: 12)))
            children.append(SizedBox(width: 8))
            children.append(SizedBox(width: 240, child: FluentTextBox(
                controller: saveNameController,
                placeholderText: "filename",
                style: TextStyle(color: c.text, fontSize: 12)
            )))
            children.append(Expanded(child: SizedBox(width: 1)))
        } else {
            let count = selected.count
            let status = count == 0
                ? currentPath
                : "\(count) item\(count == 1 ? "" : "s") selected"
            children.append(Expanded(child: Text(status, style: TextStyle(
                color: c.tertiary, fontSize: 11), overflow: .ellipsis)))
        }

        children.append(SizedBox(width: 12))
        children.append(_barButton("Cancel", bg: c.button, fg: c.buttonText) { [self] in
            panel.onComplete([])
        })
        children.append(SizedBox(width: 8))
        children.append(_barButton(options.resolvedConfirmLabel,
                                   bg: c.accent, fg: c.accentText) { [self] in
            _confirm()
        })

        return ColoredBox(
            color: c.footer,
            child: Padding(
                padding: EdgeInsets(left: 16, top: 8, right: 16, bottom: 8),
                child: Row(children: children)
            )
        )
    }

    private func _barButton(_ label: String, bg: Color, fg: Color,
                            action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: action,
            behavior: .opaque,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(5)
                ),
                child: Padding(
                    padding: EdgeInsets(left: 20, top: 6, right: 20, bottom: 6),
                    child: Text(label, style: TextStyle(color: fg, fontSize: 12))
                )
            )
        )
    }
}

// MARK: - MacosFilePanelOverlay

/// In-app modal presentation: a dimmed scrim over the app's content with the
/// panel centered as a rounded card. Embed conditionally at the top of the
/// app's Stack; taps on the scrim cancel.
public class MacosFilePanelOverlay: StatelessWidget {
    let options: MacosFilePanelOptions
    let onComplete: ([String]) -> Void
    let panelWidth: Double
    let panelHeight: Double

    public init(options: MacosFilePanelOptions,
                panelWidth: Double = 640,
                panelHeight: Double = 440,
                onComplete: @escaping ([String]) -> Void) {
        self.options = options
        self.onComplete = onComplete
        self.panelWidth = panelWidth
        self.panelHeight = panelHeight
        super.init()
    }

    public override func build(_ context: any BuildContext) -> Widget {
        return Stack(fit: .expand, children: [
            Listener(
                onPointerDown: { [self] _ in onComplete([]) },
                behavior: .opaque,
                child: ColoredBox(
                    color: Color(0x66000000),
                    child: SizedBox(expand: ())
                )
            ),
            Center(child: SizedBox(
                width: panelWidth, height: panelHeight,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius(circular: 10)),
                        boxShadow: [BoxShadow(
                            color: Color(0x59000000),
                            offset: Offset(0, 10), blurRadius: 30)]
                    ),
                    child: ClipRRect(
                        borderRadius: BorderRadius.all(Radius(circular: 10)),
                        child: MacosFilePanel(options: options, onComplete: onComplete)
                    )
                )
            )),
        ])
    }
}
