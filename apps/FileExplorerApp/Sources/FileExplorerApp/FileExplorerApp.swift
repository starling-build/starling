// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import CupertinoIcons
import Foundation
import Observation

// MARK: - Finder palette

/// Theme-aware Finder palette: `dark` is flipped by the themed root when
/// the shell pushes an appearance change. Brand colors (accent, folder
/// blue, selection) stay fixed.
/// Files' colours, in the roles the views ask for.
///
/// The VALUES come from `StarlingPalette`, which answers for whichever
/// desktop style is active: the macOS numbers this app shipped with, or
/// WinUI's own tokens when the desktop is in the Windows style. The names
/// here are unchanged, so nothing downstream learned about styles.
///
/// `folderBlue` stays a literal on purpose -- a folder is that blue on both
/// desktops, and it is the app's own mark rather than a theme colour.
enum FinderColors {
    nonisolated(unsafe) static var dark = true

    private static var p: StarlingPalette { StarlingPalette.current(dark: dark) }

    static var accent: Color { p.accent }
    /// Folder glyph blue used in the content list -- the app's own mark.
    static let folderBlue = Color(0xFF54A3F7)
    static var selection: Color { p.selection }

    static var label: Color { p.textPrimary }
    static var secondaryLabel: Color { p.textSecondary }
    static var tertiaryLabel: Color { p.textTertiary }
    static var disabled: Color { p.textDisabled }
    static var hairline: Color { p.hairline }
    static var stripe: Color { p.stripe }
    /// Toolbar control glyphs (back/forward, new-folder, eye).
    static var control: Color { p.textSecondary }
    /// Faint hero glyphs (empty-folder / search placeholder).
    static var faintGlyph: Color { p.textDisabled }
    /// Path-bar chevrons.
    static var chevron: Color { p.textTertiary }
    /// Window surfaces. The shell frosts what is behind the window and the
    /// macOS palette's alpha lets that liquid glass through, sidebar
    /// glassier than the canvas; the Fluent palette is opaque, because
    /// Windows' chrome is.
    static var glassCanvas: Color { p.canvas }
    static var glassSidebar: Color { p.sidebar }
    /// The face the active style sets its text in, or nil for the default.
    static var fontFamily: String? { p.fontFamily }
}

// MARK: - Sidebar sections

private struct _SidebarEntry {
    let name: String
    let icon: IconData
    let path: String
}

private let _sidebarSections: [(title: String, entries: [_SidebarEntry])] = {
    let realHome = realUserHomeDirectory()
    return [
        (title: "Favourites", entries: [
            _SidebarEntry(name: "Home", icon: CupertinoIcons.home, path: realHome),
            _SidebarEntry(name: "Desktop", icon: CupertinoIcons.desktopcomputer, path: realHome + "/Desktop"),
            _SidebarEntry(name: "Documents", icon: CupertinoIcons.doc_text, path: realHome + "/Documents"),
            _SidebarEntry(name: "Downloads", icon: CupertinoIcons.arrow_down_circle, path: realHome + "/Downloads"),
            _SidebarEntry(name: "Pictures", icon: CupertinoIcons.photo, path: realHome + "/Pictures"),
        ]),
        (title: "Locations", entries: [
            _SidebarEntry(name: "Root", icon: CupertinoIcons.floppy_disk, path: "/"),
            _SidebarEntry(name: "Temp", icon: CupertinoIcons.trash, path: "/tmp"),
        ]),
    ]
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

    /// Right-click context menu overlay state (window coordinates).
    var contextMenuPosition: Offset? = nil
    /// Row the context menu was opened on; nil = empty-area menu.
    var contextMenuIndex: Int? = nil

    /// Manual double-click detection: DoubleTapGestureRecognizer relies on
    /// Foundation.Timer, which never fires on the Linux DRM embedder, and a
    /// registered onDoubleTap holds the gesture arena so even onTap dies.
    private var _lastClickTime: Date = .distantPast
    private var _lastClickIndex: Int? = nil

    override func initState() {
        super.initState()
        filesBlocShared = bloc
        bloc.add(.loadInitialDirectory)
        CupertinoIcons.registerFont()
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

    // MARK: - Content

    private func _buildContent(_ context: any BuildContext) -> Widget {
        var layers: [Widget] = [
            MacosScaffold(
                children: [
                    _buildSidebar(),
                    Expanded(child: _buildMainContent(context)),
                ],
                toolBar: _buildToolBar(context),
                backgroundColor: FinderColors.glassCanvas
            )
        ]

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
                    child: SizedBox(width: 200, child: _buildContextMenu(context))
                )
            )
        }

        return Stack(children: layers)
    }

    // MARK: - Toolbar

    private func _buildToolBar(_ context: any BuildContext) -> MacosToolBar {
        let s = bloc.state
        let folderName = (s.currentPath as NSString).lastPathComponent

        return MacosToolBar(
            height: 52,
            title: Text(
                (folderName.isEmpty || folderName == "/") ? "Root" : folderName,
                style: TextStyle(
                    color: FinderColors.label,
                    fontSize: 15,
                    fontWeight: .w600
                ),
                overflow: .ellipsis,
                maxLines: 1
            ),
            leading: Row(
                children: [
                    _toolbarIconButton(
                        CupertinoIcons.chevron_left,
                        enabled: s.canGoBack
                    ) { [self] in bloc.add(.goBack) },
                    SizedBox(width: 2),
                    _toolbarIconButton(
                        CupertinoIcons.chevron_right,
                        enabled: s.canGoForward
                    ) { [self] in bloc.add(.goForward) },
                ]
            ),
            actions: [
                _toolbarIconButton(CupertinoIcons.folder_badge_plus) { [self] in
                    _showNewFolderDialog(context)
                },
                SizedBox(width: 2),
                _toolbarIconButton(
                    s.showHidden ? CupertinoIcons.eye : CupertinoIcons.eye_slash
                ) { [self] in bloc.add(.toggleHidden) },
                SizedBox(width: 10),
                SizedBox(
                    width: 170,
                    child: MacosTextField(
                        placeholder: "Search",
                        onChanged: { [self] (text: String) in
                            bloc.add(.search(text))
                        }
                    )
                ),
            ],
            titleAlignment: .centerLeft,
            // Transparent: the glass canvas shows through the toolbar.
            decoration: BoxDecoration(color: Color(0x00000000)),
            padding: EdgeInsets(horizontal: 12)
        )
    }

    private func _toolbarIconButton(_ icon: IconData, enabled: Bool = true, action: @escaping () -> Void) -> Widget {
        return MacosIconButton(
            icon: MacosIcon(
                icon: icon,
                color: enabled ? FinderColors.control : FinderColors.disabled,
                size: 16
            ),
            onPressed: enabled ? action : nil,
            disabledColor: MacosColors.transparent,
            shape: .rectangle,
            borderRadius: BorderRadius.all(Radius(circular: 5)),
            padding: EdgeInsets(all: 6)
        )
    }

    // MARK: - Sidebar

    private func _buildSidebar() -> MacosSidebar {
        let s = bloc.state
        return MacosSidebar(
            minWidth: 190,
            maxWidth: 190,
            decoration: BoxDecoration(
                color: FinderColors.glassSidebar,
                border: Border(right: BorderSide(color: FinderColors.hairline, width: 1))
            ),
            builder: { [self] (ctx: any BuildContext, _: ScrollController) in
                var children: [Widget] = []
                for (i, section) in _sidebarSections.enumerated() {
                    children.append(
                        Padding(
                            padding: EdgeInsets(left: 10, top: i == 0 ? 10 : 16, bottom: 3),
                            child: Text(
                                section.title,
                                style: TextStyle(
                                    color: FinderColors.tertiaryLabel,
                                    fontSize: 11,
                                    fontWeight: .w600
                                )
                            )
                        )
                    )
                    for entry in section.entries {
                        children.append(
                            self._sidebarItem(entry, currentPath: s.currentPath)
                        )
                    }
                }
                return Padding(
                    padding: EdgeInsets(horizontal: 8),
                    child: Column(crossAxisAlignment: .start, children: children)
                )
            }
        )
    }

    private func _sidebarItem(_ entry: _SidebarEntry, currentPath: String) -> Widget {
        let isSelected = currentPath == entry.path
        return SidebarItem(
            leading: MacosIcon(icon: entry.icon, color: FinderColors.accent, size: 16),
            label: Text(
                entry.name,
                style: TextStyle(
                    color: isSelected ? MacosColors.white : FinderColors.label,
                    fontSize: 13
                )
            ),
            selected: isSelected,
            onTap: { [self] in bloc.add(.navigateTo(entry.path)) }
        )
    }

    // MARK: - Main Content

    private func _buildMainContent(_ context: any BuildContext) -> Widget {
        let s = bloc.state

        if let error = s.errorMessage {
            return _buildErrorPage(error)
        }

        return Column(
            children: [
                _buildColumnHeaders(),
                _hairline(),
                Expanded(child: _buildFileList(context)),
                _hairline(),
                _buildPathBar(),
                _buildStatusBar(),
            ]
        )
    }

    // MARK: - Column Headers

    private let _dateColumnWidth: Double = 150
    private let _sizeColumnWidth: Double = 75
    private let _kindColumnWidth: Double = 100

    private func _buildColumnHeaders() -> Widget {
        let s = bloc.state
        return Padding(
            padding: EdgeInsets(left: 16, top: 5, right: 16, bottom: 5),
            child: Row(
                children: [
                    Expanded(child: _sortableHeader("Name", .name, s: s)),
                    _headerSeparator(),
                    SizedBox(width: _dateColumnWidth, child: _sortableHeader("Date Modified", .modified, s: s)),
                    _headerSeparator(),
                    SizedBox(
                        width: _sizeColumnWidth,
                        child: Align(alignment: Alignment.centerRight, child: _sortableHeader("Size", .size, s: s))
                    ),
                    _headerSeparator(),
                    SizedBox(width: _kindColumnWidth, child: _sortableHeader("Kind", .type, s: s)),
                ]
            )
        )
    }

    private func _headerSeparator() -> Widget {
        return Padding(
            padding: EdgeInsets(horizontal: 6),
            child: SizedBox(
                width: 1,
                height: 12,
                child: DecoratedBox(decoration: BoxDecoration(color: FinderColors.hairline))
            )
        )
    }

    private func _sortableHeader(_ label: String, _ column: SortColumn, s: FileExplorerState) -> Widget {
        let isActive = s.sortColumn == column

        var children: [Widget] = [
            Text(
                label,
                style: TextStyle(
                    color: isActive ? FinderColors.label : FinderColors.secondaryLabel,
                    fontSize: 11,
                    fontWeight: isActive ? .w600 : .normal
                )
            )
        ]
        if isActive {
            children.append(SizedBox(width: 3))
            children.append(
                MacosIcon(
                    icon: s.sortOrder == .ascending
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    color: FinderColors.secondaryLabel,
                    size: 9
                )
            )
        }

        return GestureDetector(
            onTap: { [self] in bloc.add(.toggleSort(column)) },
            child: Row(mainAxisSize: .min, children: children)
        )
    }

    // MARK: - File List

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
                    child: Column(crossAxisAlignment: .start, children: rows)
                )
            )
        )

        return MacosScrollbar(controller: scrollController, child: list)
    }

    private func _buildFileRow(_ entry: FileEntry, index: Int, isSelected: Bool) -> Widget {
        let idx = index

        let cells = Row(
            children: [
                // Icon + Name
                Expanded(
                    child: Row(
                        children: [
                            _fileIcon(entry),
                            SizedBox(width: 7),
                            Expanded(
                                child: Text(
                                    entry.name,
                                    style: TextStyle(
                                        color: isSelected ? MacosColors.white : FinderColors.label,
                                        fontSize: 13
                                    ),
                                    overflow: .ellipsis,
                                    maxLines: 1
                                )
                            ),
                        ]
                    )
                ),
                // Date Modified
                SizedBox(
                    width: _dateColumnWidth + 13,
                    child: Text(
                        FileSystem.formatDate(entry.modified),
                        style: _secondaryCellStyle(isSelected),
                        overflow: .ellipsis,
                        maxLines: 1
                    )
                ),
                // Size
                SizedBox(
                    width: _sizeColumnWidth,
                    child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                            entry.isDirectory ? "--" : FileSystem.formatSize(entry.size),
                            style: _secondaryCellStyle(isSelected)
                        )
                    )
                ),
                // Kind
                Padding(
                    padding: EdgeInsets(left: 13),
                    child: SizedBox(
                        width: _kindColumnWidth,
                        child: Text(
                            _kindLabel(entry),
                            style: _secondaryCellStyle(isSelected),
                            overflow: .ellipsis,
                            maxLines: 1
                        )
                    )
                ),
            ]
        )

        return GestureDetector(
            onTap: { [self] in
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
            },
            onSecondaryTapUp: { [self] (details: TapUpDetails) in
                bloc.add(.select(idx))
                setState {
                    contextMenuIndex = idx
                    contextMenuPosition = details.globalPosition
                }
            },
            child: ColoredBox(
                color: index % 2 == 1 ? FinderColors.stripe : Color(0x00000000),
                child: Padding(
                    padding: EdgeInsets(horizontal: 4),
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: isSelected ? FinderColors.selection : Color(0x00000000),
                            borderRadius: BorderRadius.all(Radius(circular: 5))
                        ),
                        child: Padding(
                            padding: EdgeInsets(left: 12, top: 4, right: 12, bottom: 4),
                            child: cells
                        )
                    )
                )
            )
        )
    }

    private func _secondaryCellStyle(_ isSelected: Bool) -> Flutter.TextStyle {
        return TextStyle(
            color: isSelected ? Color(0xCCFFFFFF) : FinderColors.secondaryLabel,
            fontSize: 12
        )
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
                            MacosIcon(
                                icon: isSearch ? CupertinoIcons.search : CupertinoIcons.folder_open,
                                color: FinderColors.faintGlyph,
                                size: 48
                            ),
                            SizedBox(height: 12),
                            Text(
                                isSearch ? "No results for \"\(s.searchQuery)\"" : "Empty Folder",
                                style: TextStyle(color: FinderColors.tertiaryLabel, fontSize: 13)
                            ),
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
            icon = CupertinoIcons.folder_fill
            color = FinderColors.folderBlue
        } else {
            switch entry.fileExtension {
            case "swift", "c", "cc", "cpp", "h", "py", "js", "ts", "rs", "go", "java", "rb", "sh":
                icon = CupertinoIcons.chevron_left_slash_chevron_right
                color = Color(0xFFB0B0B0)
            case "png", "jpg", "jpeg", "gif", "bmp", "svg", "ico", "webp":
                icon = CupertinoIcons.photo
                color = Color(0xFF4CD964)
            case "mp3", "wav", "flac", "aac", "ogg", "m4a":
                icon = CupertinoIcons.music_note
                color = Color(0xFFFF2D55)
            case "mp4", "mkv", "avi", "mov", "webm":
                icon = CupertinoIcons.film
                color = Color(0xFFAF52DE)
            case "zip", "tar", "gz", "bz2", "xz", "7z", "rar", "deb", "rpm":
                icon = CupertinoIcons.archivebox
                color = Color(0xFFFF9500)
            case "pdf":
                icon = CupertinoIcons.doc_text
                color = Color(0xFFFF3B30)
            case "txt", "md", "json", "xml", "yaml", "yml", "toml", "ini", "cfg", "conf", "log":
                icon = CupertinoIcons.doc_plaintext
                color = Color(0xFFB0B0B0)
            default:
                icon = CupertinoIcons.doc
                color = Color(0xFF8E8E93)
            }
        }
        return MacosIcon(icon: icon, color: color, size: 16)
    }

    private func _kindLabel(_ entry: FileEntry) -> String {
        if entry.isSymlink { return "Alias" }
        if entry.isDirectory { return "Folder" }
        switch entry.fileExtension {
        case "swift": return "Swift"
        case "c", "cc", "cpp": return "C/C++"
        case "h": return "Header"
        case "py": return "Python"
        case "js": return "JavaScript"
        case "ts": return "TypeScript"
        case "rs": return "Rust"
        case "go": return "Go"
        case "java": return "Java"
        case "sh": return "Script"
        case "png", "jpg", "jpeg", "gif", "bmp", "svg", "webp": return "Image"
        case "mp3", "wav", "flac", "aac", "ogg", "m4a": return "Audio"
        case "mp4", "mkv", "avi", "mov", "webm": return "Video"
        case "zip", "tar", "gz", "bz2", "xz", "7z", "rar": return "Archive"
        case "deb", "rpm": return "Package"
        case "pdf": return "PDF"
        case "txt": return "Text"
        case "md": return "Markdown"
        case "json": return "JSON"
        case "xml": return "XML"
        case "yaml", "yml": return "YAML"
        case "toml": return "TOML"
        case "log": return "Log"
        case "so", "dylib": return "Library"
        case "o", "a": return "Object"
        case "": return "File"
        default: return entry.fileExtension.uppercased()
        }
    }

    // MARK: - Context Menu

    private func _buildContextMenu(_ context: any BuildContext) -> Widget {
        let s = bloc.state
        var items: [MacosMenuEntry] = []

        if let idx = contextMenuIndex, idx < s.entries.count {
            let entry = s.entries[idx]
            if entry.isDirectory {
                items.append(MacosMenuItem(
                    text: "Open",
                    onPressed: { [self] in
                        setState { contextMenuPosition = nil }
                        bloc.add(.doubleClick(idx))
                    }
                ))
                items.append(MacosMenuSeparator())
            }
            items.append(MacosMenuItem(
                text: "Rename\u{2026}",
                onPressed: { [self] in
                    setState { contextMenuPosition = nil }
                    _showRenameDialog(context)
                }
            ))
            items.append(MacosMenuItem(
                text: "Delete",
                onPressed: { [self] in
                    setState { contextMenuPosition = nil }
                    _showDeleteDialog(context)
                }
            ))
            items.append(MacosMenuSeparator())
        }

        items.append(MacosMenuItem(
            text: "New Folder\u{2026}",
            onPressed: { [self] in
                setState { contextMenuPosition = nil }
                _showNewFolderDialog(context)
            }
        ))
        items.append(MacosMenuItem(
            text: "Refresh",
            onPressed: { [self] in
                setState { contextMenuPosition = nil }
                bloc.add(.refresh)
            }
        ))
        items.append(MacosMenuSeparator())
        items.append(MacosMenuItem(
            text: s.showHidden ? "Hide Hidden Files" : "Show Hidden Files",
            onPressed: { [self] in
                setState { contextMenuPosition = nil }
                bloc.add(.toggleHidden)
            }
        ))

        return MacosMenu(items: items)
    }

    // MARK: - Path Bar

    private func _buildPathBar() -> Widget {
        let s = bloc.state
        let components = FileSystem.pathComponents(s.currentPath)

        var widgets: [Widget] = []
        for (i, comp) in components.enumerated() {
            if i > 0 {
                widgets.append(
                    Padding(
                        padding: EdgeInsets(horizontal: 5),
                        child: MacosIcon(
                            icon: CupertinoIcons.chevron_right,
                            color: FinderColors.chevron,
                            size: 8
                        )
                    )
                )
            }
            let isLast = i == components.count - 1
            let isRoot = i == 0
            widgets.append(
                GestureDetector(
                    onTap: isLast ? nil : { [self] in bloc.add(.navigateTo(comp.path)) },
                    child: Row(
                        mainAxisSize: .min,
                        children: [
                            MacosIcon(
                                icon: isRoot ? CupertinoIcons.floppy_disk : CupertinoIcons.folder_fill,
                                color: isRoot ? FinderColors.secondaryLabel : FinderColors.folderBlue,
                                size: 11
                            ),
                            SizedBox(width: 4),
                            Text(
                                isRoot ? "Root" : comp.name,
                                style: TextStyle(
                                    color: isLast ? FinderColors.label : FinderColors.secondaryLabel,
                                    fontSize: 11
                                )
                            ),
                        ]
                    )
                )
            )
        }

        return DecoratedBox(
            decoration: BoxDecoration(
                border: Border(top: BorderSide(color: FinderColors.hairline, width: 0.5))
            ),
            child: SizedBox(
                height: 24,
                child: Padding(
                    padding: EdgeInsets(horizontal: 12),
                    child: SingleChildScrollView(
                        scrollDirection: .horizontal,
                        child: Row(children: widgets)
                    )
                )
            )
        )
    }

    // MARK: - Status Bar

    private func _buildStatusBar() -> Widget {
        let s = bloc.state

        var text = "\(s.entries.count) item\(s.entries.count == 1 ? "" : "s")"
        if let idx = s.selectedIndex, idx < s.entries.count {
            text = "\u{201C}\(s.entries[idx].name)\u{201D} selected of " + text
        }
        if let free = FileSystem.freeSpace(at: s.currentPath) {
            text += ", \(FileSystem.formatSize(free)) available"
        }

        return DecoratedBox(
            decoration: BoxDecoration(
                border: Border(top: BorderSide(color: FinderColors.hairline, width: 0.5))
            ),
            child: SizedBox(
                height: 22,
                child: Center(
                    child: Text(
                        text,
                        style: TextStyle(color: FinderColors.secondaryLabel, fontSize: 11)
                    )
                )
            )
        )
    }

    // MARK: - Error Page

    private func _buildErrorPage(_ error: String) -> Widget {
        return Center(
            child: Column(
                mainAxisSize: .min,
                children: [
                    MacosIcon(icon: CupertinoIcons.exclamationmark_triangle, color: Color(0xFFFF6666), size: 48),
                    SizedBox(height: 12),
                    Text(error, style: TextStyle(color: Color(0xFFFF6666), fontSize: 13)),
                    SizedBox(height: 16),
                    PushButton(
                        child: Text("Go Up"),
                        controlSize: .regular,
                        onPressed: { [self] in bloc.add(.goUp) }
                    ),
                ]
            )
        )
    }

    // MARK: - Helpers

    private func _hairline() -> Widget {
        return SizedBox(
            height: 1,
            child: DecoratedBox(
                decoration: BoxDecoration(color: FinderColors.hairline)
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
        let s = bloc.state
        guard let idx = s.selectedIndex, idx < s.entries.count else { return }
        let entry = s.entries[idx]
        showDialog(context: context, barrierDismissible: true, builder: { [self] ctx in
            return _RenameDialog(entry: entry, onRenamed: { [self] in
                bloc.add(.refresh)
            })
        })
    }

    private func _showDeleteDialog(_ context: any BuildContext) {
        let s = bloc.state
        guard let idx = s.selectedIndex, idx < s.entries.count else { return }
        let entry = s.entries[idx]
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
    var folderName: String = ""
    var error: String? = nil

    override func build(_ context: any BuildContext) -> Widget {
        return MacosAlertDialog(
            appIcon: MacosIcon(icon: CupertinoIcons.folder_badge_plus, color: Color(0xFF007AFF), size: 40),
            title: Text("New Folder"),
            message: Column(
                mainAxisSize: .min,
                children: [
                    MacosTextField(
                        placeholder: "Folder name",
                        onChanged: { [self] (text: String) in
                            setState {
                                folderName = text
                                error = nil
                            }
                        },
                        onSubmitted: { [self] (_: String) in
                            _create(context)
                        }
                    ),
                    error != nil
                        ? Padding(
                            padding: EdgeInsets(top: 8),
                            child: Text(error!, style: TextStyle(color: Color(0xFFFF6666), fontSize: 11))
                          )
                        : SizedBox(shrink: ()),
                ]
            ),
            primaryButton: PushButton(
                child: Text("Create"),
                controlSize: .regular,
                onPressed: { [self] in _create(context) }
            ),
            secondaryButton: PushButton(
                child: Text("Cancel"),
                controlSize: .regular,
                onPressed: { Navigator.pop(context) },
                secondary: true
            )
        )
    }

    private func _create(_ context: any BuildContext) {
        let dialog = widget as! _NewFolderDialog
        let name = folderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            setState { error = "Name cannot be empty" }
            return
        }
        if let err = FileSystem.createDirectory(at: dialog.parentPath, name: name) {
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
    var newName: String = ""
    var error: String? = nil

    override func initState() {
        super.initState()
        newName = (widget as! _RenameDialog).entry.name
    }

    override func build(_ context: any BuildContext) -> Widget {
        let dialog = widget as! _RenameDialog

        return MacosAlertDialog(
            appIcon: MacosIcon(icon: CupertinoIcons.pencil, color: Color(0xFF007AFF), size: 40),
            title: Text("Rename \"\(dialog.entry.name)\""),
            message: Column(
                mainAxisSize: .min,
                children: [
                    MacosTextField(
                        placeholder: "New name",
                        onChanged: { [self] (text: String) in
                            setState {
                                newName = text
                                error = nil
                            }
                        },
                        onSubmitted: { [self] (_: String) in
                            _rename(context)
                        }
                    ),
                    error != nil
                        ? Padding(
                            padding: EdgeInsets(top: 8),
                            child: Text(error!, style: TextStyle(color: Color(0xFFFF6666), fontSize: 11))
                          )
                        : SizedBox(shrink: ()),
                ]
            ),
            primaryButton: PushButton(
                child: Text("Rename"),
                controlSize: .regular,
                onPressed: { [self] in _rename(context) }
            ),
            secondaryButton: PushButton(
                child: Text("Cancel"),
                controlSize: .regular,
                onPressed: { Navigator.pop(context) },
                secondary: true
            )
        )
    }

    private func _rename(_ context: any BuildContext) {
        let dialog = widget as! _RenameDialog
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            setState { error = "Name cannot be empty" }
            return
        }
        guard name != dialog.entry.name else {
            Navigator.pop(context)
            return
        }
        if let err = FileSystem.rename(at: dialog.entry.path, to: name) {
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
        let typeLabel = entry.isDirectory ? "folder" : "file"
        return MacosAlertDialog(
            appIcon: MacosIcon(icon: CupertinoIcons.trash, color: Color(0xFFFF3B30), size: 40),
            title: Text("Delete \(typeLabel)?"),
            message: Text(
                "Are you sure you want to delete \"\(entry.name)\"? This cannot be undone.",
                style: TextStyle(color: FinderColors.label, fontSize: 13)
            ),
            primaryButton: PushButton(
                child: Text("Delete"),
                controlSize: .regular,
                onPressed: { [self] in
                    onDeleted()
                    Navigator.pop(context)
                }
            ),
            secondaryButton: PushButton(
                child: Text("Cancel"),
                controlSize: .regular,
                onPressed: { Navigator.pop(context) },
                secondary: true
            )
        )
    }
}
