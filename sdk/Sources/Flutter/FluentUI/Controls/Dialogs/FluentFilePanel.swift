// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The system open/save dialog, in Windows' shape.
//
// Windows' common file dialog is a small Explorer: a navigation row with
// back/forward/up and the address as breadcrumbs, the places pane at the
// left, a Details listing (Name, Date modified, Type, Size), and a footer
// with the file-name field and the Open/Save and Cancel buttons. This is
// that, on the Fluent controls and the theme's resources, so it takes the
// desktop's colours in either style.
//
// One implementation shared by every consumer, as before: apps embed it as
// a modal overlay (`FluentFilePanelOverlay`), and the xdg portal picker
// renders it full-window (FileExplorerApp --picker), so the desktop shows
// one file dialog everywhere. `MacosFilePanel` keeps the same options type
// for iOS.

import FlutterSwiftBridge
import Foundation
#if os(Linux)
import Glibc
#endif

// MARK: - Options

public struct FluentFilePanelOptions {
    public enum Mode {
        /// Choose existing file(s).
        case open
        /// Choose a destination: directory navigation + a filename field.
        case save
        /// Choose a directory (files are shown but not selectable).
        case directory
    }

    public var mode: Mode = .open
    public var title: String = "Open"
    public var allowsMultiple: Bool = false
    /// Lowercase extensions (no dot) selectable in open mode; nil = all.
    /// Directories always navigate regardless.
    public var allowedExtensions: [String]? = nil
    public var initialDirectory: String? = nil
    /// Seed for the save-mode filename field.
    public var suggestedName: String? = nil
    /// Confirm-button label; defaults to Open/Save/Select Folder per mode.
    public var confirmLabel: String? = nil
    /// Explicit dark/light override. Apps without a theme ancestor
    /// (custom-chrome apps) set this; otherwise the theme decides.
    public var appearanceDark: Bool? = nil

    public init() {}

    var resolvedConfirmLabel: String {
        if let l = confirmLabel, !l.isEmpty { return l }
        switch mode {
        case .open: return "Open"
        case .save: return "Save"
        case .directory: return "Select Folder"
        }
    }
}

/// The name the macOS panel was written against; one options type for both.
public typealias MacosFilePanelOptions = FluentFilePanelOptions

// MARK: - Glyphs

/// The Fluent System Icons this dialog draws, by code point. The
/// `FluentSystemIcons` module depends on this one, so the roles it names
/// cannot be imported here; these are the same glyphs (keep in step with
/// `sdk/Sources/FluentSystemIcons/FluentSystemIcons.swift`), loaded by
/// `StarlingFonts` when first drawn.
private enum _Glyph {
    static let family = "FluentSystemIcons"
    static let back = IconData(0xf15c, fontFamily: family)
    static let forward = IconData(0xf182, fontFamily: family)
    static let up = IconData(0xf19c, fontFamily: family)
    static let chevronRight = IconData(0xf2b1, fontFamily: family)
    static let folder = IconData(0xf419, fontFamily: family)
    static let folderOpen = IconData(0xf42f, fontFamily: family)
    static let zip = IconData(0xf436, fontFamily: family)
    static let home = IconData(0xf481, fontFamily: family)
    static let desktop = IconData(0xf35a, fontFamily: family)
    static let download = IconData(0xf151, fontFamily: family)
    static let document = IconData(0xf379, fontFamily: family)
    static let pictures = IconData(0xf489, fontFamily: family)
    static let music = IconData(0xe855, fontFamily: family)
    static let video = IconData(0xf84d, fontFamily: family)
    static let laptop = IconData(0xf4c4, fontFamily: family)
}

// MARK: - Directory listing

/// One row of the dialog's file list. Self-contained (the framework can't
/// reach app-side file helpers).
struct FluentFilePanelEntry {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let modified: Date

    var fileExtension: String {
        isDirectory ? "" : (name as NSString).pathExtension.lowercased()
    }

    var icon: IconData {
        if isDirectory { return _Glyph.folder }
        switch fileExtension {
        case "png", "jpg", "jpeg", "gif", "bmp", "svg", "ico", "webp", "ppm":
            return _Glyph.pictures
        case "mp3", "wav", "flac", "aac", "ogg", "m4a":
            return _Glyph.music
        case "mp4", "mkv", "avi", "mov", "webm":
            return _Glyph.video
        case "zip", "tar", "gz", "bz2", "xz", "7z", "rar", "deb", "rpm":
            return _Glyph.zip
        default:
            return _Glyph.document
        }
    }

    /// Explorer's Type column, by extension.
    var typeLabel: String {
        if isDirectory { return "File folder" }
        switch fileExtension {
        case "": return "File"
        case "txt": return "Text document"
        case "md": return "Markdown document"
        case "pdf": return "PDF document"
        case "rtf": return "Rich text document"
        case "png", "jpg", "jpeg", "gif", "bmp", "svg", "webp", "ppm":
            return "\(fileExtension.uppercased()) image"
        case "mp3", "wav", "flac", "aac", "ogg", "m4a":
            return "\(fileExtension.uppercased()) audio"
        case "mp4", "mkv", "avi", "mov", "webm":
            return "\(fileExtension.uppercased()) video"
        case "zip", "tar", "gz", "bz2", "xz", "7z", "rar": return "Archive"
        default: return "\(fileExtension.uppercased()) file"
        }
    }

    static func list(_ path: String, showHidden: Bool) -> [FluentFilePanelEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var out: [FluentFilePanelEntry] = []
        for name in names {
            if !showHidden && name.hasPrefix(".") { continue }
            let p = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &isDir) else { continue }
            let attrs = try? fm.attributesOfItem(atPath: p)
            let size = (attrs?[.size] as? UInt64) ?? 0
            let modified = (attrs?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
            out.append(FluentFilePanelEntry(
                name: name, path: p, isDirectory: isDir.boolValue, size: size,
                modified: modified))
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

    private static let _dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy HH:mm"
        return f
    }()

    static func formatDate(_ date: Date) -> String {
        _dateFormat.string(from: date)
    }
}

// MARK: - FluentFilePanel

/// The dialog content. Fills whatever box it is given — the portal picker
/// uses it as the whole window; in-app consumers wrap it in
/// `FluentFilePanelOverlay`.
public class FluentFilePanel: StatefulWidget {
    let options: FluentFilePanelOptions
    /// Selected absolute paths; empty means cancelled.
    let onComplete: ([String]) -> Void

    public init(options: FluentFilePanelOptions,
                onComplete: @escaping ([String]) -> Void) {
        self.options = options
        self.onComplete = onComplete
        super.init()
    }

    public override func createState() -> State<StatefulWidget> {
        return _FluentFilePanelState()
    }
}

private let kPanelNavBar = 44.0
private let kPanelSidebar = 200.0
private let kPanelHeaderRow = 26.0
private let kPanelRow = 28.0
private let kPanelFooter = 64.0
private let kColModified = 150.0
private let kColType = 120.0
private let kColSize = 80.0

class _FluentFilePanelState: State<StatefulWidget> {
    private var panel: FluentFilePanel { widget as! FluentFilePanel }
    private var options: FluentFilePanelOptions { panel.options }

    private var currentPath = ""
    private var history: [String] = []
    private var historyIndex = 0
    private var entries: [FluentFilePanelEntry] = []
    private var selected: Set<Int> = []
    private var showHidden = false

    // Manual double-click detection: a registered onDoubleTap holds the
    // gesture arena on the Linux DRM embedder (Foundation.Timer never
    // fires) and kills onTap — same workaround as the Files app.
    private var _lastClickTime = Date.distantPast
    private var _lastClickIndex: Int? = nil

    private let saveNameController = TextEditingController()
    private let scrollController = ScrollController()

    private static var _home: String { realUserHomeDirectory() }

    /// Explorer's places: Home, the pinned folders that exist, This PC.
    private var places: [(name: String, icon: IconData, path: String)] {
        let home = Self._home
        let fm = FileManager.default
        var out: [(String, IconData, String)] = [("Home", _Glyph.home, home)]
        let pinned: [(String, IconData, String)] = [
            ("Desktop", _Glyph.desktop, home + "/Desktop"),
            ("Documents", _Glyph.document, home + "/Documents"),
            ("Downloads", _Glyph.download, home + "/Downloads"),
            ("Pictures", _Glyph.pictures, home + "/Pictures"),
            ("Music", _Glyph.music, home + "/Music"),
            ("Videos", _Glyph.video, home + "/Videos"),
        ]
        for p in pinned where fm.fileExists(atPath: p.2) { out.append(p) }
        out.append(("This PC", _Glyph.laptop, "/"))
        return out
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

    override func dispose() {
        saveNameController.dispose()
        super.dispose()
    }

    // MARK: Navigation

    private func _load(_ path: String) {
        currentPath = path
        entries = FluentFilePanelEntry.list(path, showHidden: showHidden)
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
    private var canGoForward: Bool { historyIndex < history.count - 1 }
    private var canGoUp: Bool { currentPath != "/" }

    // MARK: Selection semantics

    /// Whether a row can be part of the result (directories are always
    /// navigable but only selectable in directory mode).
    private func _selectable(_ entry: FluentFilePanelEntry) -> Bool {
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

    private struct _Ink {
        let theme: FluentThemeData
        var r: ResourceDictionary { theme.resources }
        var surface: Color { r.solidBackgroundFillColorBase }
        var navPane: Color { r.layerFillColorDefault }
        var listBg: Color { r.solidBackgroundFillColorTertiary }
        var footer: Color { r.solidBackgroundFillColorBase }
        var hairline: Color { r.dividerStrokeColorDefault }
        var text: Color { r.textFillColorPrimary }
        var secondary: Color { r.textFillColorSecondary }
        var tertiary: Color { r.textFillColorTertiary }
        var disabled: Color { r.textFillColorDisabled }
        var hover: Color { r.subtleFillColorSecondary }
        var fieldFill: Color { r.controlFillColorDefault }
        var fieldBorder: Color { r.controlStrokeColorDefault }
        var accent: Color { theme.accentColor.defaultBrushFor(theme.brightness) }
        var selection: Color { accent.withValues(alpha: 0.22) }
        /// A folder's glyph: Explorer's yellow. (Framework code cannot see
        /// `StarlingPalette`'s per-style folder colour.)
        var folder: Color { theme.brightness == .dark ? Color(0xFFF2C14E) : Color(0xFFE8B33B) }
        var font: String? { theme.typography.body?.fontFamily }
    }

    private func _text(_ s: String, _ ink: _Ink, size: Double = 12, color: Color? = nil) -> Widget {
        Text(s, style: TextStyle(color: color ?? ink.text, fontSize: size, fontFamily: ink.font),
             overflow: .ellipsis, maxLines: 1)
    }

    override func build(_ context: any BuildContext) -> Widget {
        var theme = FluentTheme.of(context)
        if let dark = options.appearanceDark, (theme.brightness == .dark) != dark {
            theme = dark ? FluentThemeData.dark() : FluentThemeData.light()
        }
        let ink = _Ink(theme: theme)
        return FluentTheme(
            data: theme,
            child: ColoredBox(
                color: ink.surface,
                child: Column(children: [
                    _navigationBar(ink),
                    Expanded(child: Row(crossAxisAlignment: .stretch, children: [
                        SizedBox(width: kPanelSidebar, child: _sidebar(ink)),
                        Expanded(child: ColoredBox(
                            color: ink.listBg,
                            child: Column(children: [
                                _columnHeaders(ink),
                                Expanded(child: _fileList(ink)),
                            ]))),
                    ])),
                    _hairline(ink),
                    _footer(ink),
                ])
            )
        )
    }

    private func _hairline(_ ink: _Ink) -> Widget {
        SizedBox(height: 1, child: ColoredBox(color: ink.hairline, child: SizedBox(expand: ())))
    }

    // MARK: Navigation bar

    private func _navigationBar(_ ink: _Ink) -> Widget {
        return SizedBox(
            height: kPanelNavBar,
            child: Padding(
                padding: EdgeInsets(left: 8, top: 6, right: 8, bottom: 6),
                child: Row(children: [
                    _navIcon(_Glyph.back, enabled: canGoBack) { [self] in
                        setState { historyIndex -= 1; _load(history[historyIndex]) }
                    },
                    _navIcon(_Glyph.forward, enabled: canGoForward) { [self] in
                        setState { historyIndex += 1; _load(history[historyIndex]) }
                    },
                    _navIcon(_Glyph.up, enabled: canGoUp) { [self] in
                        setState { _navigate((currentPath as NSString).deletingLastPathComponent) }
                    },
                    SizedBox(width: 6),
                    Expanded(child: _breadcrumb(ink)),
                ])))
    }

    private func _navIcon(_ icon: IconData, enabled: Bool, _ action: @escaping () -> Void) -> Widget {
        IconButton(icon: Icon(icon, size: 14), onPressed: enabled ? action : nil)
    }

    /// The address as crumbs in a field, each one a place to go back to.
    private func _breadcrumb(_ ink: _Ink) -> Widget {
        var all: [(name: String, path: String)] = [("This PC", "/")]
        var acc = ""
        for comp in currentPath.split(separator: "/") {
            acc += "/" + comp
            all.append((String(comp), acc))
        }
        var crumbs: [Widget] = [
            Icon(_Glyph.laptop, size: 12, color: ink.secondary),
            SizedBox(width: 4),
        ]
        // The last four components; an ellipsis stands for the rest.
        let shown = Array(all.suffix(4))
        if all.count > shown.count {
            crumbs.append(_text("\u{2026}", ink, color: ink.tertiary))
            crumbs.append(Icon(_Glyph.chevronRight, size: 8, color: ink.tertiary))
        }
        for (i, crumb) in shown.enumerated() {
            if i > 0 {
                crumbs.append(Icon(_Glyph.chevronRight, size: 8, color: ink.tertiary))
            }
            let isLast = i == shown.count - 1
            let target = crumb.path
            crumbs.append(GestureDetector(
                onTap: isLast ? nil : { [self] in setState { _navigate(target) } },
                child: Padding(
                    padding: EdgeInsets(horizontal: 5, vertical: 3),
                    child: _text(crumb.name, ink, color: isLast ? ink.text : ink.secondary))))
        }
        crumbs.append(Expanded(child: SizedBox(height: 1)))
        return DecoratedBox(
            decoration: BoxDecoration(
                color: ink.fieldFill,
                border: Border.all(color: ink.fieldBorder, width: 1),
                borderRadius: BorderRadius.circular(FluentCorners.control)),
            child: SizedBox(
                height: 32,
                child: Padding(
                    padding: EdgeInsets(horizontal: 10),
                    child: ClipRect(child: Row(children: crumbs)))))
    }

    // MARK: Places

    private func _sidebar(_ ink: _Ink) -> Widget {
        var rows: [Widget] = []
        for place in places {
            let isActive = currentPath == place.path
            let p = place.path
            rows.append(Padding(
                padding: EdgeInsets(vertical: 1),
                child: HoverButton(
                    builder: { [self] _, states in
                        ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: ColoredBox(
                                color: isActive ? ink.selection
                                    : (states.isHovered ? ink.hover : Color(0x00000000)),
                                child: SizedBox(
                                    height: 30,
                                    child: Padding(
                                        padding: EdgeInsets(horizontal: 10),
                                        child: Row(children: [
                                            Icon(place.icon, size: 14,
                                                 color: place.path == "/" ? ink.secondary : ink.folder),
                                            SizedBox(width: 9),
                                            Expanded(child: _text(place.name, ink, size: 13)),
                                        ])))))
                    },
                    onPressed: { [self] in setState { _navigate(p) } })))
        }
        return ColoredBox(
            color: ink.navPane,
            child: Padding(
                padding: EdgeInsets(left: 8, top: 8, right: 8, bottom: 8),
                child: Column(crossAxisAlignment: .stretch, children: rows)))
    }

    // MARK: Listing

    private func _columnHeaders(_ ink: _Ink) -> Widget {
        return SizedBox(
            height: kPanelHeaderRow,
            child: Padding(
                padding: EdgeInsets(horizontal: 12),
                child: Row(children: [
                    SizedBox(width: 26),
                    Expanded(child: _text("Name", ink, size: 11, color: ink.tertiary)),
                    SizedBox(width: kColModified, child: _text("Date modified", ink, size: 11, color: ink.tertiary)),
                    SizedBox(width: kColType, child: _text("Type", ink, size: 11, color: ink.tertiary)),
                    SizedBox(width: kColSize, child: Align(
                        alignment: Alignment.centerRight,
                        child: _text("Size", ink, size: 11, color: ink.tertiary))),
                ])))
    }

    private func _fileList(_ ink: _Ink) -> Widget {
        if entries.isEmpty {
            return Center(child: Column(mainAxisSize: .min, children: [
                Icon(_Glyph.folderOpen, size: 40, color: ink.disabled),
                SizedBox(height: 10),
                _text("This folder is empty.", ink, size: 13, color: ink.tertiary),
            ]))
        }
        var rows: [Widget] = []
        for (index, entry) in entries.enumerated() {
            rows.append(_row(entry, index: index, ink))
        }
        // SingleChildScrollView + Column (not ListView): the proven scroll
        // path for DMA-BUF children — see the Files/Settings apps.
        return FluentScrollbar(
            controller: scrollController,
            child: SingleChildScrollView(
                controller: scrollController,
                child: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows)))
    }

    private func _row(_ entry: FluentFilePanelEntry, index: Int, _ ink: _Ink) -> Widget {
        let isSelected = selected.contains(index)
        let selectable = _selectable(entry)
        let idx = index
        let isDir = entry.isDirectory
        let dim = selectable || isDir ? ink.secondary : ink.disabled
        return HoverButton(
            builder: { [self] _, states in
                ColoredBox(
                    color: isSelected ? ink.selection
                        : (states.isHovered ? ink.hover : Color(0x00000000)),
                    child: SizedBox(
                        height: kPanelRow,
                        child: Padding(
                            padding: EdgeInsets(horizontal: 12),
                            child: Row(children: [
                                SizedBox(width: 16, height: 16, child: Center(child: Icon(
                                    entry.icon, size: 15,
                                    color: isDir ? ink.folder : (selectable ? ink.secondary : ink.disabled)))),
                                SizedBox(width: 10),
                                Expanded(child: _text(entry.name, ink, color: selectable || isDir ? ink.text : ink.disabled)),
                                SizedBox(width: kColModified, child: _text(
                                    FluentFilePanelEntry.formatDate(entry.modified), ink, color: dim)),
                                SizedBox(width: kColType, child: _text(entry.typeLabel, ink, color: dim)),
                                SizedBox(width: kColSize, child: Align(
                                    alignment: Alignment.centerRight,
                                    child: _text(isDir ? "" : FluentFilePanelEntry.formatSize(entry.size),
                                                 ink, color: dim))),
                            ]))))
            },
            onPressed: { [self] in
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
            })
    }

    // MARK: Footer

    private func _footer(_ ink: _Ink) -> Widget {
        var children: [Widget] = []
        if options.mode == .save {
            children.append(_text("File name:", ink, size: 14, color: ink.secondary))
            children.append(SizedBox(width: 12))
            children.append(Expanded(child: FluentTextBox(
                controller: saveNameController,
                placeholderText: "File name",
                onSubmitted: { [self] _ in _confirm() })))
        } else {
            let count = selected.count
            let status = count == 0
                ? ""
                : "\(count) item\(count == 1 ? "" : "s") selected"
            children.append(Expanded(child: _text(status, ink, size: 12, color: ink.tertiary)))
        }
        children.append(SizedBox(width: 16))
        children.append(FilledButton(onPressed: { [self] in _confirm() },
                                     child: Text(options.resolvedConfirmLabel)))
        children.append(SizedBox(width: 8))
        children.append(Button(onPressed: { [self] in panel.onComplete([]) },
                               child: Text("Cancel")))
        return ColoredBox(
            color: ink.footer,
            child: SizedBox(
                height: kPanelFooter,
                child: Padding(
                    padding: EdgeInsets(horizontal: 16),
                    child: Row(crossAxisAlignment: .center, children: children))))
    }
}

// MARK: - FluentFilePanelOverlay

/// In-app modal presentation: Smoke over the app's content with the
/// dialog centred as an elevation-128 card. Embed conditionally at the
/// top of the app's Stack; a click on the smoke or Esc cancels.
public class FluentFilePanelOverlay: StatefulWidget {
    let options: FluentFilePanelOptions
    let onComplete: ([String]) -> Void
    let panelWidth: Double
    let panelHeight: Double

    public init(options: FluentFilePanelOptions,
                panelWidth: Double = 760,
                panelHeight: Double = 500,
                onComplete: @escaping ([String]) -> Void) {
        self.options = options
        self.onComplete = onComplete
        self.panelWidth = panelWidth
        self.panelHeight = panelHeight
        super.init()
    }

    public override func createState() -> State<StatefulWidget> {
        return _FluentFilePanelOverlayState()
    }
}

class _FluentFilePanelOverlayState: State<StatefulWidget> {
    private var overlay: FluentFilePanelOverlay { widget as! FluentFilePanelOverlay }
    private var _dismissToken: DismissStack.Token?

    override func initState() {
        super.initState()
        _dismissToken = DismissStack.push { [weak self] in self?.overlay.onComplete([]) }
    }

    override func dispose() {
        DismissStack.remove(_dismissToken)
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        var theme = FluentTheme.of(context)
        if let dark = overlay.options.appearanceDark, (theme.brightness == .dark) != dark {
            theme = dark ? FluentThemeData.dark() : FluentThemeData.light()
        }
        let radius = BorderRadius.circular(FluentCorners.overlay)
        return Stack(fit: .expand, children: [
            Listener(
                onPointerDown: { [self] _ in overlay.onComplete([]) },
                behavior: .opaque,
                child: Smoke()
            ),
            Center(child: SizedBox(
                width: overlay.panelWidth, height: overlay.panelHeight,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        border: Border.all(color: theme.resources.surfaceStrokeColorDefault,
                                           width: FluentStrokeWidth.thin),
                        borderRadius: radius,
                        boxShadow: FluentElevation.shadows(128, brightness: theme.brightness)
                    ),
                    child: ClipRRect(
                        borderRadius: radius,
                        child: FluentFilePanel(options: overlay.options,
                                               onComplete: overlay.onComplete)
                    )
                )
            )),
        ])
    }
}
