// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Files, in Explorer's shape (docs/plans/fluent-first.md, Phase 6): a
// command bar, a navigation bar carrying the breadcrumb and the search box,
// the places pane at the left, a Details listing with Explorer's four
// columns, and a status bar. The Windows shell's Files.swift was built to
// exactly this spec and is the layout reference — the heights, widths and
// type sizes below are its. The behaviour is FileExplorerBloc's, unchanged.
//
// Not here: the tab strip. Explorer's tabs live in the title bar, and a
// DMA-BUF child does not own its title bar — the shell draws it. One
// listing per window, honestly.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation
import Observation

// MARK: - Palette

/// Files' colours, in the roles the views ask for.
///
/// The VALUES come from `StarlingPalette`, which answers for whichever
/// desktop style is active — WinUI's tokens in the Windows style, the macOS
/// numbers in the other. `dark` is flipped by the root's onThemeChanged
/// before the rebuild, so every var here reads the right side.
enum FinderColors {
    nonisolated(unsafe) static var dark = true

    private static var p: StarlingPalette { StarlingPalette.current(dark: dark) }

    static var accent: Color { p.accent }
    /// A folder's glyph — the palette's, because Explorer's are yellow and
    /// Finder's blue.
    static var folder: Color { p.folder }
    static var label: Color { p.textPrimary }
    static var secondaryLabel: Color { p.textSecondary }
    static var tertiaryLabel: Color { p.textTertiary }
    static var disabled: Color { p.textDisabled }
    static var hairline: Color { p.hairline }
    static var hover: Color { p.hover }
    /// A selected row: the accent, faint, under unchanged text — Explorer's
    /// selection, not Finder's solid bar.
    static var rowSelection: Color {
        let a = p.accent
        return Color(alpha: 0.22, red: a.r, green: a.g, blue: a.b)
    }
    /// Faint hero glyphs (empty-folder / search placeholder).
    static var faintGlyph: Color { p.textDisabled }
    /// The chrome: command bar, navigation bar, status bar, places pane.
    static var chrome: Color { p.canvas }
    static var navPane: Color { p.sidebar }
    /// The listing, lifted a shade off the chrome as Explorer's is.
    static var listBg: Color { p.surface }
    static var fieldFill: Color { p.fieldFill }
    static var fieldBorder: Color { p.fieldBorder }
    /// The face the active style sets its text in, or nil for the default.
    static var fontFamily: String? { p.fontFamily }
}

// MARK: - Geometry (Explorer's)

private let kCommandBar = 44.0
private let kNavBar = 44.0
private let kHeaderRow = 26.0
private let kRow = 28.0
private let kSidebar = 220.0
private let kStatusBar = 34.0
private let kColModified = 170.0
private let kColType = 130.0
private let kColSize = 90.0

// MARK: - Places

private struct _Place {
    let name: String
    let icon: IconData
    let path: String
    var pinned: Bool = false
}

private let _home = realUserHomeDirectory()

/// Explorer's pane, on a Linux home: Home first, the pinned folders under
/// it (the ones that exist), then the machine and the bin.
private let _placesHome = _Place(name: "Home", icon: FluentSystemIcons.home, path: _home)
private let _placesPinned: [_Place] = [
    _Place(name: "Desktop",   icon: FluentSystemIcons.desktop,  path: _home + "/Desktop",   pinned: true),
    _Place(name: "Documents", icon: FluentSystemIcons.document, path: _home + "/Documents", pinned: true),
    _Place(name: "Downloads", icon: FluentSystemIcons.download, path: _home + "/Downloads", pinned: true),
    _Place(name: "Pictures",  icon: FluentSystemIcons.pictures, path: _home + "/Pictures",  pinned: true),
    _Place(name: "Music",     icon: FluentSystemIcons.music,    path: _home + "/Music",     pinned: true),
    _Place(name: "Videos",    icon: FluentSystemIcons.video,    path: _home + "/Videos",    pinned: true),
].filter { FileManager.default.fileExists(atPath: $0.path) }
private let _placesComputer = _Place(name: "This PC", icon: FluentSystemIcons.laptop, path: "/")
private let _placesTrash: _Place? = {
    let path = _home + "/.local/share/Trash/files"
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    return _Place(name: "Recycle Bin", icon: FluentSystemIcons.delete, path: path)
}()

// MARK: - FileExplorerApp

class FileExplorerApp: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _FileExplorerAppState()
    }
}

class _FileExplorerAppState: State<StatefulWidget>, @unchecked Sendable {

    let bloc = FileExplorerBloc()
    let scrollController = ScrollController()
    private let search = TextEditingController()

    /// Right-click context menu overlay state (window coordinates).
    var contextMenuPosition: Offset? = nil
    /// Row the context menu was opened on; nil = empty-area menu.
    var contextMenuIndex: Int? = nil

    /// The breadcrumb's edit face: open, its controller, and the directory
    /// it was opened on (a navigation under it closes it).
    private var pathEditing = false
    private var pathController: TextEditingController? = nil
    private var pathEditDirectory = ""

    /// Manual double-click detection: DoubleTapGestureRecognizer relies on
    /// Foundation.Timer, which never fires on the Linux DRM embedder, and a
    /// registered onDoubleTap holds the gesture arena so even onTap dies.
    private var _lastClickTime: Date = .distantPast
    private var _lastClickIndex: Int? = nil

    /// Ctrl+X/C/V over the listing. The framework routes keys to one
    /// focused node, so the listing holds one and gives it up whenever the
    /// search box or a dialog field takes focus — which is exactly right:
    /// Ctrl+C in the search box belongs to the search box.
    private let _keys = FocusNode(debugLabel: "FilesListing")
    /// Whether Ctrl is down. Child apps are sent X11 keysyms in `logical`
    /// (the DRM embedder's convention — the shell's own widgets switch on
    /// HID `physical` instead, and copying that here would match nothing).
    private var _ctrlDown = false

    override func initState() {
        super.initState()
        filesBlocShared = bloc
        bloc.add(.loadInitialDirectory)
        _keys.onKeyData = { [weak self] key in self?._handleKey(key) ?? false }
        _keys.requestFocus()
    }

    /// Returns true when the key was ours; anything else falls through —
    /// Escape especially, which the dismiss stack needs to hear.
    private func _handleKey(_ key: KeyData) -> Bool {
        let down = key.type == .down || key.type == .repeat
        switch key.logical {
        case 0xFFE3, 0xFFE4:  // Control_L / Control_R
            _ctrlDown = down
            return false
        default:
            break
        }
        guard down, _ctrlDown else { return false }
        switch key.logical {
        case 0x63, 0x43:  // c / C
            _clip(cut: false); return true
        case 0x78, 0x58:  // x / X
            _clip(cut: true); return true
        case 0x76, 0x56:  // v / V
            if bloc.state.canPaste { bloc.add(.paste) }
            return true
        default:
            return false
        }
    }

    override func dispose() {
        search.dispose()
        pathController?.dispose()
        _keys.dispose()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        return withObservationTracking {
            _buildContent(context)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.setState {}
            }
        }
    }

    private var selectedEntry: FileEntry? {
        let s = bloc.state
        guard let idx = s.selectedIndex, idx < s.entries.count else { return nil }
        return s.entries[idx]
    }

    private func _text(_ text: String, size: Double = 12, color: Color? = nil,
                       weight: FontWeight = .normal) -> Widget {
        return Text(
            text,
            style: TextStyle(color: color ?? FinderColors.label, fontSize: size,
                             fontWeight: weight, fontFamily: FinderColors.fontFamily),
            overflow: .ellipsis, maxLines: 1)
    }

    // MARK: - Content

    private func _buildContent(_ context: any BuildContext) -> Widget {
        let s = bloc.state
        let main: Widget = s.errorMessage.map { _buildErrorPage($0) }
            ?? Column(children: [
                _buildColumnHeaders(),
                Expanded(child: _buildFileList(context)),
            ])

        var layers: [Widget] = [
            ColoredBox(
                color: FinderColors.chrome,
                child: Column(children: [
                    _buildCommandBar(context),
                    _buildNavigationBar(),
                    Expanded(child: Row(children: [
                        _buildSidebar(),
                        Expanded(child: ColoredBox(color: FinderColors.listBg, child: main)),
                    ])),
                    _buildStatusBar(),
                ])
            ),
        ]

        if !s.pasteConflicts.isEmpty {
            layers.append(Positioned(fill: (), child: _ConflictOverlay(
                names: s.pasteConflicts,
                cut: s.clipboard?.cut ?? false,
                onResolve: { [self] policy in bloc.add(.resolvePaste(policy)) },
                onCancel: { [self] in bloc.add(.cancelPaste) })))
        }

        if let pos = contextMenuPosition {
            // Full-window barrier that dismisses the menu on any click.
            layers.append(
                Positioned(
                    fill: (),
                    child: Listener(
                        onPointerDown: { [self] _ in
                            setState { contextMenuPosition = nil }
                        },
                        behavior: .opaque,
                        child: ColoredBox(
                            color: Color(0x00000000),
                            child: SizedBox(expand: ())
                        )
                    )
                )
            )
            layers.append(
                Positioned(
                    left: pos.dx,
                    top: pos.dy,
                    child: _menu(_contextMenu(context))
                )
            )
        }

        return Stack(children: layers)
    }

    /// Cut or copy the selection. One item, because the listing selects
    /// one — the clipboard itself holds a list and is ready for more.
    private func _clip(cut: Bool) {
        guard let entry = selectedEntry else { return }
        bloc.add(.clip(path: entry.path, cut: cut))
    }

    /// A flyout as plain content in the window's own Stack, placed at the
    /// pointer — the shape the shell uses for its popups. The intrinsic
    /// wrappers are what give it a size to lay out in; without them it
    /// renders as nothing.
    private func _menu(_ content: Widget) -> Widget {
        return ConstrainedBox(
            constraints: kFlyoutThemeConstraints,
            child: IntrinsicWidth(child: IntrinsicHeight(
                child: FluentEntrance(child: content))))
    }

    // MARK: - Command bar

    /// New, then the verbs the listing supports, then Sort and View —
    /// Explorer's order, without Share, which needs somewhere to share to.
    private func _buildCommandBar(_ context: any BuildContext) -> Widget {
        let s = bloc.state
        let selected = selectedEntry
        let sortItems: [MenuFlyoutItemBase] = [
            _sortItem("Name", .name, s),
            _sortItem("Date modified", .modified, s),
            _sortItem("Type", .type, s),
            _sortItem("Size", .size, s),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("Ascending"),
                           onPressed: { [self] in _setSortOrder(ascending: true) },
                           selected: s.sortOrder == .ascending),
            MenuFlyoutItem(text: Text("Descending"),
                           onPressed: { [self] in _setSortOrder(ascending: false) },
                           selected: s.sortOrder == .descending),
        ]
        return SizedBox(
            height: kCommandBar,
            child: Padding(
                padding: EdgeInsets(horizontal: 10),
                child: Row(children: [
                    DropDownButton(
                        title: Text("New"),
                        leading: Icon(FluentSystemIcons.add, size: 14),
                        items: [
                            MenuFlyoutItem(
                                text: Text("Folder"),
                                leading: Icon(FluentSystemIcons.folder, size: 14),
                                onPressed: { [self] in _showNewFolderDialog(context) }),
                        ]),
                    _barSeparator(),
                    IconButton(
                        icon: Icon(FluentSystemIcons.cut, size: 14),
                        onPressed: selected == nil ? nil : { [self] in _clip(cut: true) }),
                    SizedBox(width: 2),
                    IconButton(
                        icon: Icon(FluentSystemIcons.copy, size: 14),
                        onPressed: selected == nil ? nil : { [self] in _clip(cut: false) }),
                    SizedBox(width: 2),
                    IconButton(
                        icon: Icon(FluentSystemIcons.paste, size: 14),
                        onPressed: s.canPaste ? { [self] in bloc.add(.paste) } : nil),
                    SizedBox(width: 2),
                    IconButton(
                        icon: Icon(FluentSystemIcons.rename, size: 14),
                        onPressed: selected == nil ? nil : { [self] in _showRenameDialog(context) }),
                    SizedBox(width: 2),
                    IconButton(
                        icon: Icon(FluentSystemIcons.delete, size: 14),
                        onPressed: selected == nil ? nil : { [self] in _showDeleteDialog(context) }),
                    _barSeparator(),
                    DropDownButton(
                        title: Text("Sort"),
                        leading: Icon(FluentSystemIcons.sort, size: 14),
                        items: sortItems),
                    SizedBox(width: 2),
                    DropDownButton(
                        title: Text("View"),
                        leading: Icon(FluentSystemIcons.grid, size: 14),
                        items: [
                            MenuFlyoutItem(
                                text: Text("Show hidden items"),
                                onPressed: { [self] in bloc.add(.toggleHidden) },
                                selected: s.showHidden),
                        ]),
                ])
            )
        )
    }

    private func _sortItem(_ label: String, _ column: SortColumn, _ s: FileExplorerState) -> MenuFlyoutItem {
        return MenuFlyoutItem(
            text: Text(label),
            onPressed: { [self] in
                if bloc.state.sortColumn != column { bloc.add(.toggleSort(column)) }
            },
            selected: s.sortColumn == column)
    }

    private func _setSortOrder(ascending: Bool) {
        let s = bloc.state
        if (s.sortOrder == .ascending) != ascending {
            bloc.add(.toggleSort(s.sortColumn))
        }
    }

    private func _barSeparator() -> Widget {
        return Padding(
            padding: EdgeInsets(horizontal: 6, vertical: 10),
            child: SizedBox(
                width: 1,
                child: DecoratedBox(decoration: BoxDecoration(color: FinderColors.hairline))))
    }

    // MARK: - Navigation bar

    /// Back, forward, up, refresh, the breadcrumb, and search.
    private func _buildNavigationBar() -> Widget {
        let s = bloc.state
        return SizedBox(
            height: kNavBar,
            child: Padding(
                padding: EdgeInsets(left: 10, top: 0, right: 10, bottom: 6),
                child: Row(children: [
                    _navIcon(FluentSystemIcons.back, enabled: s.canGoBack) { [self] in bloc.add(.goBack) },
                    _navIcon(FluentSystemIcons.forward, enabled: s.canGoForward) { [self] in bloc.add(.goForward) },
                    _navIcon(FluentSystemIcons.up, enabled: s.canGoUp) { [self] in bloc.add(.goUp) },
                    _navIcon(FluentSystemIcons.refresh, enabled: true) { [self] in bloc.add(.refresh) },
                    SizedBox(width: 6),
                    Expanded(child: _breadcrumb()),
                    SizedBox(width: 8),
                    _searchBox(),
                ])
            )
        )
    }

    private func _navIcon(_ icon: IconData, enabled: Bool, _ action: @escaping () -> Void) -> Widget {
        return IconButton(
            icon: Icon(icon, size: 15),
            onPressed: enabled ? action : nil)
    }

    /// The address bar, as Explorer draws it: the path broken into
    /// segments with chevrons between them, each one a place you can go
    /// back to — and, on a click in its empty space, an edit field over the
    /// same footprint. Enter navigates; losing focus puts the crumbs back.
    private func _breadcrumb() -> Widget {
        let s = bloc.state
        // A navigation that lands UNDER the edit closes it: the field was
        // editing a directory this window is no longer in.
        if pathEditing && s.currentPath != pathEditDirectory {
            pathEditing = false
            pathController = nil
        }
        if pathEditing { return _pathField() }

        let parts = FileSystem.pathComponents(s.currentPath)
        var crumbs: [Widget] = [
            Icon(FluentSystemIcons.laptop, size: 13, color: FinderColors.secondaryLabel),
            SizedBox(width: 4),
        ]
        for (i, part) in parts.enumerated() {
            if i > 0 {
                crumbs.append(Icon(FluentSystemIcons.chevronRight, size: 9,
                                   color: FinderColors.tertiaryLabel))
            }
            let isLast = i == parts.count - 1
            let label = i == 0 ? "This PC" : part.name
            crumbs.append(GestureDetector(
                onTap: isLast ? nil : { [self] in bloc.add(.navigateTo(part.path)) },
                child: Padding(
                    padding: EdgeInsets(horizontal: 5, vertical: 3),
                    child: _text(label, size: 12,
                                 color: isLast ? FinderColors.label : FinderColors.secondaryLabel))))
        }
        // The empty remainder of the bar IS the edit affordance. A
        // transparent ColoredBox, because a bare SizedBox hit-tests as
        // nothing and this framework's ColoredBox hit-tests opaque at any
        // alpha — the documented trap, here load-bearing.
        crumbs.append(Expanded(child: GestureDetector(
            onTap: { [self] in _openPathEdit() },
            child: ColoredBox(color: Color(0x00000000), child: SizedBox(height: 32)))))

        return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: FinderColors.fieldFill,
                    border: Border.all(color: FinderColors.fieldBorder, width: 1),
                    borderRadius: BorderRadius.circular(4)),
                child: SizedBox(
                    height: 32,
                    child: Padding(
                        padding: EdgeInsets(horizontal: 10),
                        child: Row(children: crumbs)))))
    }

    private func _pathField() -> Widget {
        return SizedBox(
            height: 32,
            child: FluentTextBox(
                controller: pathController!,
                onSubmitted: { [self] text in _commitPath(text) },
                autofocus: true,
                // Losing focus IS the dismissal: Explorer's bar folds back
                // to crumbs the moment the edit stops being the focus.
                onFocusChanged: { [self] focused in
                    guard !focused, pathEditing else { return }
                    setState {
                        pathEditing = false
                        pathController = nil
                    }
                }))
    }

    private func _openPathEdit() {
        let directory = bloc.state.currentPath
        setState {
            let controller = TextEditingController(text: directory)
            // Everything selected, as Explorer opens it: the common gesture
            // is typing a whole new path over the old one, not appending to
            // it. Without this the first keystroke lands after the path and
            // types "/home/starling/home/starling/…".
            controller.selection = TextSelection(baseOffset: 0,
                                                 extentOffset: directory.count)
            pathController = controller
            pathEditing = true
            pathEditDirectory = directory
        }
    }

    /// Enter in the address field: expand a leading ~, then go if the
    /// directory exists. A typo stays in the field to be fixed.
    private func _commitPath(_ text: String) {
        var path = text.trimmingCharacters(in: .whitespaces)
        if path.hasPrefix("~") { path = _home + path.dropFirst() }
        guard !path.isEmpty else {
            setState { pathEditing = false; pathController = nil }
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        setState { pathEditing = false; pathController = nil }
        bloc.add(.navigateTo(path))
    }

    private func _searchBox() -> Widget {
        let folder = (bloc.state.currentPath as NSString).lastPathComponent
        return SizedBox(
            width: 220, height: 32,
            child: FluentTextBox(
                controller: search,
                placeholderText: "Search \(folder.isEmpty ? "This PC" : folder)",
                onChanged: { [self] (text: String) in bloc.add(.search(text)) },
                prefix: Padding(
                    padding: EdgeInsets(left: 8),
                    child: Icon(FluentSystemIcons.search, size: 12,
                                color: FinderColors.tertiaryLabel))))
    }

    // MARK: - Places pane

    private func _buildSidebar() -> Widget {
        let s = bloc.state
        var rows: [Widget] = [_placeRow(_placesHome, current: s.currentPath)]
        if !_placesPinned.isEmpty {
            rows.append(_sidebarRule())
            for place in _placesPinned {
                rows.append(_placeRow(place, current: s.currentPath))
            }
        }
        rows.append(_sidebarRule())
        rows.append(_placeRow(_placesComputer, current: s.currentPath))
        if let trash = _placesTrash {
            rows.append(_placeRow(trash, current: s.currentPath))
        }
        return SizedBox(
            width: kSidebar,
            child: ColoredBox(
                color: FinderColors.navPane,
                child: Padding(
                    padding: EdgeInsets(left: 8, top: 10, right: 8, bottom: 8),
                    child: Column(crossAxisAlignment: .stretch, children: rows))))
    }

    /// The hairline between pane groups, inset the way Explorer's are.
    private func _sidebarRule() -> Widget {
        return Padding(
            padding: EdgeInsets(left: 10, top: 8, right: 10, bottom: 8),
            child: SizedBox(
                height: 1,
                child: DecoratedBox(decoration: BoxDecoration(color: FinderColors.hairline))))
    }

    private func _placeRow(_ place: _Place, current: String) -> Widget {
        let selected = current == place.path
        return Padding(
            padding: EdgeInsets(vertical: 1),
            child: HoverButton(
                builder: { _, states in
                    var cells: [Widget] = [
                        Icon(place.icon, size: 14,
                             color: place.pinned || place.path == _home
                                 ? FinderColors.folder : FinderColors.secondaryLabel),
                        SizedBox(width: 9),
                        Expanded(child: self._text(place.name, size: 13)),
                    ]
                    if place.pinned {
                        cells.append(Icon(FluentSystemIcons.pin, size: 11,
                                          color: FinderColors.tertiaryLabel))
                    }
                    return ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: ColoredBox(
                            color: selected ? FinderColors.rowSelection
                                : (states.isHovered ? FinderColors.hover : Color(0x00000000)),
                            child: SizedBox(
                                height: 30,
                                child: Padding(
                                    padding: EdgeInsets(horizontal: 10),
                                    child: Row(children: cells)))))
                },
                onPressed: { [self] in bloc.add(.navigateTo(place.path)) }))
    }

    // MARK: - Column headers

    /// Name / Date modified / Type / Size, and a click sorts by one.
    private func _buildColumnHeaders() -> Widget {
        let s = bloc.state
        return SizedBox(
            height: kHeaderRow,
            child: Padding(
                padding: EdgeInsets(horizontal: 16),
                child: Row(children: [
                    SizedBox(width: 18, height: 1),
                    SizedBox(width: 10),
                    Expanded(child: _headerCell("Name", .name, s: s, leading: true)),
                    SizedBox(width: 10),
                    SizedBox(width: kColModified, child: _headerCell("Date modified", .modified, s: s, leading: true)),
                    SizedBox(width: 10),
                    SizedBox(width: kColType, child: _headerCell("Type", .type, s: s, leading: true)),
                    SizedBox(width: 10),
                    SizedBox(width: kColSize, child: _headerCell("Size", .size, s: s, leading: false)),
                ])))
    }

    private func _headerCell(_ label: String, _ column: SortColumn, s: FileExplorerState,
                             leading: Bool) -> Widget {
        let active = s.sortColumn == column
        var children: [Widget] = [
            _text(label, size: 11, color: active ? FinderColors.label : FinderColors.tertiaryLabel),
        ]
        if active {
            // The arrow is the only thing that says which way a re-click
            // will flip it.
            children.append(SizedBox(width: 4))
            children.append(Icon(
                s.sortOrder == .ascending ? FluentSystemIcons.chevronUp : FluentSystemIcons.chevronDown,
                size: 8, color: FinderColors.accent))
        }
        return GestureDetector(
            onTap: { [self] in bloc.add(.toggleSort(column)) },
            behavior: .opaque,
            child: Align(
                alignment: leading ? Alignment.centerLeft : Alignment.centerRight,
                child: Row(mainAxisSize: .min, crossAxisAlignment: .center, children: children)))
    }

    // MARK: - Listing

    private func _buildFileList(_ context: any BuildContext) -> Widget {
        let s = bloc.state

        if s.entries.isEmpty {
            return _buildEmptyState(s)
        }

        var rows: [Widget] = []
        for (index, entry) in s.entries.enumerated() {
            rows.append(_buildFileRow(entry, index: index, isSelected: s.selectedIndex == index))
        }

        // Right-click on the area below the rows opens the folder menu.
        let list = GestureDetector(
            onSecondaryTapUp: { [self] (details: TapUpDetails) in
                setState {
                    contextMenuIndex = nil
                    contextMenuPosition = details.globalPosition
                }
            },
            child: ColoredBox(
                color: Color(0x00000000),
                child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(crossAxisAlignment: .stretch, children: rows)
                )
            )
        )

        return FluentScrollbar(controller: scrollController, child: list)
    }

    private func _buildFileRow(_ entry: FileEntry, index: Int, isSelected: Bool) -> Widget {
        let idx = index
        let dim = FinderColors.secondaryLabel

        let row = HoverButton(
            builder: { [self] _, states in
                ColoredBox(
                    color: isSelected ? FinderColors.rowSelection
                        : (states.isHovered ? FinderColors.hover : Color(0x00000000)),
                    child: SizedBox(
                        height: kRow,
                        child: Padding(
                            padding: EdgeInsets(horizontal: 16),
                            child: Row(children: [
                                SizedBox(width: 18, height: 18, child: Center(child: _fileIcon(entry))),
                                SizedBox(width: 10),
                                Expanded(child: _text(entry.name, size: 12)),
                                SizedBox(width: 10),
                                SizedBox(
                                    width: kColModified,
                                    child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: _text(FileSystem.formatDate(entry.modified), size: 12, color: dim))),
                                SizedBox(width: 10),
                                SizedBox(
                                    width: kColType,
                                    child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: _text(_kindLabel(entry), size: 12, color: dim))),
                                SizedBox(width: 10),
                                SizedBox(
                                    width: kColSize,
                                    child: Align(
                                        alignment: Alignment.centerRight,
                                        child: _text(entry.isDirectory ? "" : FileSystem.formatSize(entry.size),
                                                     size: 12, color: dim))),
                            ]))))
            },
            onPressed: { [self] in
                // A click in the listing takes the keyboard back from the
                // search box, so Ctrl+C works again without a detour.
                _keys.requestFocus()
                // Select on the first click, open on a second within 0.4s.
                let now = Date()
                if _lastClickIndex == idx, now.timeIntervalSince(_lastClickTime) < 0.4 {
                    _lastClickTime = .distantPast
                    _lastClickIndex = nil
                    bloc.add(.doubleClick(idx))
                } else {
                    _lastClickTime = now
                    _lastClickIndex = idx
                    bloc.add(.select(idx))
                }
            })

        return GestureDetector(
            onSecondaryTapUp: { [self] (details: TapUpDetails) in
                bloc.add(.select(idx))
                setState {
                    contextMenuIndex = idx
                    contextMenuPosition = details.globalPosition
                }
            },
            child: row)
    }

    private func _buildEmptyState(_ s: FileExplorerState) -> Widget {
        let isSearch = !s.searchQuery.isEmpty
        return GestureDetector(
            onSecondaryTapUp: { [self] (details: TapUpDetails) in
                setState {
                    contextMenuIndex = nil
                    contextMenuPosition = details.globalPosition
                }
            },
            child: ColoredBox(
                color: Color(0x00000000),
                child: Center(
                    child: Column(
                        mainAxisSize: .min,
                        children: [
                            Icon(isSearch ? FluentSystemIcons.search : FluentSystemIcons.folderOpen,
                                 size: 48, color: FinderColors.faintGlyph),
                            SizedBox(height: 12),
                            _text(isSearch ? "No items match your search." : "This folder is empty.",
                                  size: 13, color: FinderColors.tertiaryLabel),
                        ]
                    )
                )
            )
        )
    }

    private func _fileIcon(_ entry: FileEntry) -> Widget {
        let icon: IconData
        let color: Color
        if entry.isDirectory {
            icon = FluentSystemIcons.folder
            color = FinderColors.folder
        } else {
            switch entry.fileExtension {
            case "png", "jpg", "jpeg", "gif", "bmp", "svg", "ico", "webp":
                icon = FluentSystemIcons.pictures
                color = Color(0xFF4CD964)
            case "mp3", "wav", "flac", "aac", "ogg", "m4a":
                icon = FluentSystemIcons.music
                color = Color(0xFFFF2D55)
            case "mp4", "mkv", "avi", "mov", "webm":
                icon = FluentSystemIcons.video
                color = Color(0xFFAF52DE)
            case "zip", "tar", "gz", "bz2", "xz", "7z", "rar", "deb", "rpm":
                icon = FluentSystemIcons.zip
                color = Color(0xFFFF9500)
            default:
                icon = FluentSystemIcons.document
                color = FinderColors.secondaryLabel
            }
        }
        return Icon(icon, size: 16, color: color)
    }

    /// Explorer's Type column: "File folder", then the kind by extension.
    private func _kindLabel(_ entry: FileEntry) -> String {
        if entry.isSymlink { return "Shortcut" }
        if entry.isDirectory { return "File folder" }
        switch entry.fileExtension {
        case "swift": return "Swift source"
        case "c", "cc", "cpp": return "C/C++ source"
        case "h": return "C header"
        case "py": return "Python source"
        case "js": return "JavaScript source"
        case "ts": return "TypeScript source"
        case "rs": return "Rust source"
        case "go": return "Go source"
        case "java": return "Java source"
        case "sh": return "Shell script"
        case "png", "jpg", "jpeg", "gif", "bmp", "svg", "webp":
            return "\(entry.fileExtension.uppercased()) image"
        case "mp3", "wav", "flac", "aac", "ogg", "m4a":
            return "\(entry.fileExtension.uppercased()) audio"
        case "mp4", "mkv", "avi", "mov", "webm":
            return "\(entry.fileExtension.uppercased()) video"
        case "zip", "tar", "gz", "bz2", "xz", "7z", "rar": return "Archive"
        case "deb", "rpm": return "Package"
        case "pdf": return "PDF document"
        case "txt": return "Text document"
        case "md": return "Markdown document"
        case "json": return "JSON file"
        case "xml": return "XML file"
        case "yaml", "yml": return "YAML file"
        case "toml": return "TOML file"
        case "log": return "Log file"
        case "so", "dylib": return "Shared library"
        case "o", "a": return "Object file"
        case "": return "File"
        default: return "\(entry.fileExtension.uppercased()) file"
        }
    }

    // MARK: - Context menu

    /// Explorer's context menu: the commands that act on the item as a row
    /// of icons across the top, everything else as a menu under them
    /// (`CommandBarFlyout`, which is what Microsoft recommends a context
    /// menu be built from). Right-clicking the empty area below the rows
    /// acts on the folder, so it gets the menu alone — as Explorer's own
    /// background menu has no icon row either.
    ///
    /// The row is Windows' own, minus Share, which needs a target to share
    /// with. Paste belongs to the FOLDER rather than to an item, so it is
    /// in the background menu rather than the row — as Explorer has it.
    private func _contextMenu(_ context: any BuildContext) -> Widget {
        let s = bloc.state
        let close: () -> Void = { [self] in setState { contextMenuPosition = nil } }
        var primary: [CommandBarItem] = []
        var secondary: [CommandBarItem] = []

        if let idx = contextMenuIndex, idx < s.entries.count {
            let entry = s.entries[idx]
            primary.append(CommandBarButton(
                icon: Icon(FluentSystemIcons.cut),
                onPressed: { [self] in close(); _clip(cut: true) }, tooltip: "Cut"))
            primary.append(CommandBarButton(
                icon: Icon(FluentSystemIcons.copy),
                onPressed: { [self] in close(); _clip(cut: false) }, tooltip: "Copy"))
            primary.append(CommandBarButton(
                icon: Icon(FluentSystemIcons.rename), onPressed: { [self] in close(); _showRenameDialog(context) },
                tooltip: "Rename"))
            primary.append(CommandBarButton(
                icon: Icon(FluentSystemIcons.delete), onPressed: { [self] in close(); _showDeleteDialog(context) },
                tooltip: "Delete"))
            if entry.isDirectory {
                secondary.append(CommandBarButton(
                    icon: Icon(FluentSystemIcons.folderOpen), label: Text("Open"),
                    onPressed: { [self] in close(); bloc.add(.doubleClick(idx)) }))
                secondary.append(CommandBarSeparator())
            }
        }

        // Paste acts on the FOLDER, so Explorer offers it when the click
        // landed on the background and not when it landed on an item.
        if contextMenuIndex == nil, s.canPaste {
            secondary.append(CommandBarButton(
                icon: Icon(FluentSystemIcons.paste), label: Text("Paste"),
                onPressed: { [self] in close(); bloc.add(.paste) }))
            secondary.append(CommandBarSeparator())
        }
        secondary.append(CommandBarButton(
            icon: Icon(FluentSystemIcons.folderAdd), label: Text("New folder"),
            onPressed: { [self] in close(); _showNewFolderDialog(context) }))
        secondary.append(CommandBarButton(
            icon: Icon(FluentSystemIcons.refresh), label: Text("Refresh"),
            onPressed: { [self] in close(); bloc.add(.refresh) }))
        secondary.append(CommandBarSeparator())
        secondary.append(CommandBarToggleButton(
            label: Text("Show hidden items"), isChecked: s.showHidden,
            onChanged: { [self] _ in close(); bloc.add(.toggleHidden) }))

        return CommandBarFlyout(
            primaryCommands: primary,
            secondaryCommands: secondary,
            // A context menu opens showing everything, and Explorer's
            // cannot be folded back up.
            initiallyExpanded: true,
            alwaysExpanded: true,
            onDismiss: close)
    }

    // MARK: - Status bar

    /// Explorer's status bar: how many things are here, what is picked,
    /// and how much room is left.
    private func _buildStatusBar() -> Widget {
        let s = bloc.state
        let count = s.entries.count
        // A copy in flight, or the last one's failure, says so here rather
        // than in the error page — a paste that failed on one file must not
        // take the folder listing away.
        if let busy = s.busy {
            return SizedBox(
                height: kStatusBar,
                child: Padding(
                    padding: EdgeInsets(horizontal: 14),
                    child: Row(crossAxisAlignment: .center, children: [
                        SizedBox(width: 14, height: 14,
                                 child: ProgressRing(strokeWidth: 2)),
                        SizedBox(width: 10),
                        _text(busy, size: 11, color: FinderColors.secondaryLabel),
                    ])))
        }
        var cells: [Widget] = [
            _text("\(count) item\(count == 1 ? "" : "s")", size: 11, color: FinderColors.secondaryLabel),
        ]
        if let failure = s.operationError {
            cells.append(SizedBox(width: 12))
            cells.append(Flexible(child: _text(failure, size: 11, color: Color(0xFFE0655A))))
        }
        if let entry = selectedEntry {
            cells.append(Padding(
                padding: EdgeInsets(horizontal: 12),
                child: SizedBox(
                    width: 1, height: 14,
                    child: DecoratedBox(decoration: BoxDecoration(color: FinderColors.hairline)))))
            cells.append(Flexible(child: _text(
                entry.isDirectory ? "1 item selected"
                    : "1 item selected  \(FileSystem.formatSize(entry.size))",
                size: 11, color: FinderColors.secondaryLabel)))
        }
        if let free = FileSystem.freeSpace(at: s.currentPath) {
            cells.append(Expanded(child: Align(
                alignment: Alignment.centerRight,
                child: _text("\(FileSystem.formatSize(free)) free", size: 11,
                             color: FinderColors.secondaryLabel))))
        }
        return SizedBox(
            height: kStatusBar,
            child: Padding(
                padding: EdgeInsets(left: 14, top: 0, right: 10, bottom: 0),
                child: Row(crossAxisAlignment: .center, children: cells)))
    }

    // MARK: - Error page

    private func _buildErrorPage(_ error: String) -> Widget {
        return Center(
            child: Column(
                mainAxisSize: .min,
                children: [
                    Icon(FluentSystemIcons.info, size: 48, color: FinderColors.faintGlyph),
                    SizedBox(height: 12),
                    _text(error, size: 13, color: FinderColors.secondaryLabel),
                    SizedBox(height: 16),
                    Button(onPressed: { [self] in bloc.add(.goUp) }, child: Text("Go up")),
                ]
            )
        )
    }

    // MARK: - Dialogs

    private func _showNewFolderDialog(_ context: any BuildContext) {
        showDialog(context: context, barrierDismissible: true, builder: { [self] ctx in
            return _NewFolderDialog(parentPath: bloc.state.currentPath, onCreated: { [self] in
                bloc.add(.refresh)
            })
        })
    }

    private func _showRenameDialog(_ context: any BuildContext) {
        guard let entry = selectedEntry else { return }
        showDialog(context: context, barrierDismissible: true, builder: { [self] ctx in
            return _RenameDialog(entry: entry, onRenamed: { [self] in
                bloc.add(.refresh)
            })
        })
    }

    private func _showDeleteDialog(_ context: any BuildContext) {
        guard let entry = selectedEntry else { return }
        showDialog(context: context, barrierDismissible: true, builder: { [self] ctx in
            return _DeleteDialog(entry: entry, onDeleted: { [self] in
                bloc.add(.delete(path: entry.path))
            })
        })
    }
}

// MARK: - New Folder Dialog

class _NewFolderDialog: StatefulWidget {
    let parentPath: String
    let onCreated: () -> Void

    init(parentPath: String, onCreated: @escaping () -> Void) {
        self.parentPath = parentPath
        self.onCreated = onCreated
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        return _NewFolderDialogState()
    }
}

class _NewFolderDialogState: State<StatefulWidget> {
    private let name = TextEditingController(text: "New folder")
    var error: String? = nil

    override func dispose() {
        name.dispose()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        var content: [Widget] = [
            FluentTextBox(
                controller: name,
                placeholderText: "Folder name",
                onChanged: { [self] _ in if error != nil { setState { error = nil } } },
                onSubmitted: { [self] _ in _create(context) },
                autofocus: true),
        ]
        if let error {
            content.append(Padding(
                padding: EdgeInsets(top: 8),
                child: Text(error, style: TextStyle(color: Color(0xFFE0655A), fontSize: 12))))
        }
        return ContentDialog(
            title: Text("New folder"),
            content: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: content),
            actions: [
                Button(onPressed: { Navigator.pop(context) }, child: Text("Cancel")),
                FilledButton(onPressed: { [self] in _create(context) }, child: Text("Create")),
            ])
    }

    private func _create(_ context: any BuildContext) {
        let dialog = widget as! _NewFolderDialog
        let folder = name.text.trimmingCharacters(in: .whitespaces)
        guard !folder.isEmpty else {
            setState { error = "Name cannot be empty" }
            return
        }
        if let err = FileSystem.createDirectory(at: dialog.parentPath, name: folder) {
            setState { error = err }
        } else {
            dialog.onCreated()
            Navigator.pop(context)
        }
    }
}

// MARK: - Rename Dialog

class _RenameDialog: StatefulWidget {
    let entry: FileEntry
    let onRenamed: () -> Void

    init(entry: FileEntry, onRenamed: @escaping () -> Void) {
        self.entry = entry
        self.onRenamed = onRenamed
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        return _RenameDialogState()
    }
}

class _RenameDialogState: State<StatefulWidget> {
    private var name: TextEditingController? = nil
    var error: String? = nil

    override func initState() {
        super.initState()
        name = TextEditingController(text: (widget as! _RenameDialog).entry.name)
    }

    override func dispose() {
        name?.dispose()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let dialog = widget as! _RenameDialog
        var content: [Widget] = [
            FluentTextBox(
                controller: name!,
                placeholderText: "New name",
                onChanged: { [self] _ in if error != nil { setState { error = nil } } },
                onSubmitted: { [self] _ in _rename(context) },
                autofocus: true),
        ]
        if let error {
            content.append(Padding(
                padding: EdgeInsets(top: 8),
                child: Text(error, style: TextStyle(color: Color(0xFFE0655A), fontSize: 12))))
        }
        return ContentDialog(
            title: Text("Rename \"\(dialog.entry.name)\""),
            content: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: content),
            actions: [
                Button(onPressed: { Navigator.pop(context) }, child: Text("Cancel")),
                FilledButton(onPressed: { [self] in _rename(context) }, child: Text("Rename")),
            ])
    }

    private func _rename(_ context: any BuildContext) {
        let dialog = widget as! _RenameDialog
        let newName = (name?.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else {
            setState { error = "Name cannot be empty" }
            return
        }
        guard newName != dialog.entry.name else {
            Navigator.pop(context)
            return
        }
        if let err = FileSystem.rename(at: dialog.entry.path, to: newName) {
            setState { error = err }
        } else {
            dialog.onRenamed()
            Navigator.pop(context)
        }
    }
}

// MARK: - Delete Confirmation Dialog

class _DeleteDialog: StatelessWidget {
    let entry: FileEntry
    let onDeleted: () -> Void

    init(entry: FileEntry, onDeleted: @escaping () -> Void) {
        self.entry = entry
        self.onDeleted = onDeleted
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let kind = entry.isDirectory ? "folder" : "file"
        return ContentDialog(
            title: Text("Delete \(kind)?"),
            content: Text("Are you sure you want to permanently delete \"\(entry.name)\"?"),
            actions: [
                Button(onPressed: { Navigator.pop(context) }, child: Text("Cancel")),
                FilledButton(
                    onPressed: { [self] in
                        onDeleted()
                        Navigator.pop(context)
                    },
                    child: Text("Delete")),
            ])
    }
}

// MARK: - Replace or skip

/// Explorer's question when a paste lands on a name that is already taken,
/// and its three answers. Shown in the window's own Stack rather than
/// through `showDialog`, because the pending paste is BLOC state: a route
/// popped by Escape would be rebuilt from that state and reappear. Esc
/// cancels the paste instead, through the dismiss stack.
private final class _ConflictOverlay: StatefulWidget {
    let names: [String]
    let cut: Bool
    let onResolve: (FileSystem.ConflictPolicy) -> Void
    let onCancel: () -> Void

    init(names: [String], cut: Bool,
         onResolve: @escaping (FileSystem.ConflictPolicy) -> Void,
         onCancel: @escaping () -> Void) {
        self.names = names
        self.cut = cut
        self.onResolve = onResolve
        self.onCancel = onCancel
        super.init()
    }

    override func createState() -> State<StatefulWidget> { _ConflictOverlayState() }
}

private final class _ConflictOverlayState: State<StatefulWidget> {
    private var overlay: _ConflictOverlay { widget as! _ConflictOverlay }
    private var _dismiss: DismissStack.Token?

    override func initState() {
        super.initState()
        _dismiss = DismissStack.push { [weak self] in self?.overlay.onCancel() }
    }

    override func dispose() {
        DismissStack.remove(_dismiss)
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let names = overlay.names
        let verb = overlay.cut ? "moving" : "copying"
        let what = names.count == 1
            ? "There is already a file named \"\(names[0])\" here."
            : "\(names.count) items here already have the same names."
        return Stack(fit: .expand, children: [
            Listener(
                onPointerDown: { [self] _ in overlay.onCancel() },
                behavior: .opaque,
                child: Smoke()),
            Center(child: ContentDialog(
                title: Text("Replace or skip?"),
                content: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
                    Text("\(what) Choose what to do while \(verb)."),
                ]),
                actions: [
                    FilledButton(onPressed: { [self] in overlay.onResolve(.replace) },
                                 child: Text("Replace")),
                    Button(onPressed: { [self] in overlay.onResolve(.keepBoth) },
                           child: Text("Keep both")),
                    Button(onPressed: { [self] in overlay.onResolve(.skip) },
                           child: Text("Skip")),
                ])),
        ])
    }
}
