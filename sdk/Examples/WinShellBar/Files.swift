// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The file explorer.
//
// An ordinary window, like Settings, and for the same reasons: it is an app,
// and a normal Column/Row is the input path that works in this framework.
//
// SHAPED LIKE WINDOWS 11'S EXPLORER, deliberately: the tab strip, the command
// bar, the breadcrumb-and-search row, the four Details columns, the status
// bar. Someone who knows Explorer should not have to learn anything.
//
// What is NOT here is the point of the exercise. Explorer's command bar verbs
// — new, cut, copy, paste, rename, delete — need IFileOperation and the undo
// and recycle-bin semantics that come with it, and none of that is written.
// Those buttons are therefore DRAWN DISABLED rather than drawn working: the
// layout is honest about the shape and honest about the capability, and a
// button that silently does nothing is worse than one that says it cannot.
// The verbs that ARE implemented — navigate, sort, filter, open, open-with,
// hand off to Explorer — are live.

#if os(Windows)
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import FlutterWin32Bridge
import Foundation
import Observation

let kFilesSidebar = 220.0
let kFilesRow = 28.0
/// Explorer's three stacked bars, and the column-header strip under them.
/// Everything above the list, which is what the row arithmetic measures from.
let kFilesTabStrip = 38.0
let kFilesCommandBar = 44.0
let kFilesNavBar = 44.0
let kFilesHeaderRow = 26.0
let kFilesToolbar = kFilesTabStrip + kFilesCommandBar + kFilesNavBar + kFilesHeaderRow
/// The window the explorer opens at, in logical points -- named because the
/// tree needs it too: a menu that has to flip up when it would run off the
/// bottom has to know where the bottom is. The live size is read from the
/// window (it is resizable); this is the fallback and the size main.swift
/// creates it at.
let kFilesWidth = 1040.0
let kFilesHeight = 680.0

let kFilesStatusBar = 34.0

/// The Details columns, at Explorer's proportions. Name takes what is left.
let kFilesColModified = 170.0
let kFilesColType = 130.0
let kFilesColSize = 90.0

/// Windows 11 dark, sampled from Explorer rather than invented, so the two
/// sitting side by side do not disagree about what "dark" is.
enum Win11 {
    static let windowBg = Color(0xFF202020)
    static let surface = Color(0xFF272727)
    static let navPane = Color(0xFF202020)
    static let listBg = Color(0xFF272727)
    static let stroke = Color(0xFF383838)
    static let text = Color(0xFFFFFFFF)
    static let textDim = Color(0xFFC5C5C5)
    static let textFaint = Color(0xFF8A8A8A)
    static let disabled = Color(0xFF5A5A5A)
    static let accent = Color(0xFF4CC2FF)
    static let selection = Color(0x332F9CF4)
    static let hoverFill = Color(0x14FFFFFF)
    static let fieldFill = Color(0xFF2D2D2D)
    /// The context menu, sampled from Explorer's own: a near-opaque slab with
    /// a lighter hairline around it, not the app's window colours.
    static let menuBg = Color(0xFA2C2C2C)
    static let menuBorder = Color(0xFF454545)
    static let menuHover = Color(0xFF383838)
    static let menuSep = Color(0xFF3D3D3D)
}

final class StarlingFiles: StatefulWidget {
    override func createState() -> State<StatefulWidget> { StarlingFilesState() }
}

final class StarlingFilesState: State<StatefulWidget> {
    private let bloc = filesBloc

    /// Double-click, by hand.
    ///
    /// `onDoubleTap` is not usable here — registering it kills the plain tap
    /// as well on at least one embedder, and this framework's gesture arena
    /// is not something to rely on. So: a tap selects, and a second tap on
    /// the same row within the interval opens. Windows' own behaviour, out of
    /// two ordinary taps.
    private var lastTapPath: String?
    private var lastTapAt = Date.distantPast

    /// The list's scroll position, so a right-click can work out which row is
    /// under the pointer. Without it the arithmetic is only right until the
    /// first scroll — and then silently wrong, which is worse.
    private let scroll = ScrollController()

    /// The search box's text. Owned by the widget, not the bloc: the bloc
    /// holds the filter it produced, which is a different thing from what is
    /// currently in the field.
    private let search = TextEditingController()

    /// The context menu, which is a surface of its own from here on.
    ///
    /// It holds its own state and draws through its own widget, so moving the
    /// highlight from one row to the next rebuilds two panels rather than
    /// this window -- measured at 3.9ms of CPU per row change when a hover
    /// went through `setState` here, against a listing that can be ten
    /// thousand rows long.
    private let menu = ShellMenuModel()

    override func initState() {
        super.initState()
        CupertinoIcons.registerFont()
        // The listing is the only thing the menu cannot work out for itself.
        menu.target = { [weak self] x, y in self?.targetAt(x, y) }
        bloc.add(.start)
    }

    override func build(_ context: any BuildContext) -> Widget {
        withObservationTracking {
            _buildContent()
        } onChange: { [weak self] in
            guard let self, self.mounted else { return }
            self.setState {}
        }
    }

    private func _buildContent() -> Widget {
        Directionality(
            textDirection: .ltr,
            child: Listener(
                onPointerDown: { e in
                    // 2 is the secondary button, and a PRESS rather than a
                    // release — the same choice the dock makes, for the same
                    // reason: the press is what arrives reliably, and every
                    // desktop opens its menus on it anyway.
                    if self.menu.isOpen {
                        self.menu.press(e.position.dx, e.position.dy,
                                        buttons: e.buttons)
                        return
                    }
                    if e.buttons == 2 {
                        self.menu.open(at: e.position.dx, e.position.dy)
                    }
                },
                // The highlight, and what opens a submenu — Windows opens
                // them on hover and so does this. Only while a menu is down:
                // this fires for every pointer move over the whole window.
                onPointerHover: { e in
                    guard self.menu.isOpen else { return }
                    self.menu.hovered(e.position.dx, e.position.dy)
                },
                child: ColoredBox(color: Win11.windowBg) {
                Stack(alignment: Alignment.topLeft) {
                    Column(crossAxisAlignment: .stretch) {
                    tabStrip()
                    Expanded {
                    Row(crossAxisAlignment: .stretch) {
                        sidebar()
                        Expanded {
                            Column(crossAxisAlignment: .stretch) {
                                commandBar()
                                navigationBar()
                                columnHeaders()
                                Expanded {
                                    ColoredBox(color: Win11.listBg) { listing() }
                                }
                                statusBar()
                            }
                        }
                    }
                    }
                    }
                    // Always mounted, drawing nothing when there is no menu:
                    // a Stack that GAINS a child does not reliably composite
                    // it, and a widget that came and went would take the
                    // model's observation with it. Filling the stack rather
                    // than being placed by it, because where the panels go is
                    // the menu's business -- this window does not rebuild
                    // when they move.
                    Positioned(left: 0, top: 0, right: 0, bottom: 0) {
                        StarlingContextMenu(model: menu)
                    }
                }
            }))
    }

    // MARK: - What is under a right-click
    //
    // The one part of the context menu the LISTING owns, and the reason the
    // model asks rather than works it out: which rows exist and how far they
    // have been scrolled is this surface's business and nobody else's.
    // Everything past this point -- the rows, the geometry, the session, the
    // drawing -- is FilesMenu.swift.

    /// The row under a point, accounting for how far the list is scrolled.
    /// nil above the listing (the toolbars, the sidebar) so no menu opens
    /// there, and `.background` in the empty space below the last row, which
    /// is what gets the folder's own menu.
    private func targetAt(_ x: Double, _ y: Double) -> MenuTarget? {
        guard x >= kFilesSidebar, y >= kFilesToolbar else { return nil }
        let index = Int((y - kFilesToolbar + scroll.offset) / kFilesRow)
        guard index >= 0, index < bloc.state.visible.count else { return .background }
        return .item(bloc.state.visible[index])
    }

    // MARK: - Sidebar

    private func sidebar() -> Widget {
        SizedBox(width: kFilesSidebar) {
            ColoredBox(color: Win11.navPane) {
                Padding(padding: EdgeInsets(left: 8, top: 6, right: 8, bottom: 8)) {
                    Column(crossAxisAlignment: .stretch) {
                        sidebarHeading("Home")
                        for place in bloc.state.places { placeRow(place) }
                        SizedBox(height: 12)
                        sidebarHeading("This PC")
                        for drive in bloc.state.drives { placeRow(drive) }
                    }
                }
            }
        }
    }

    private func sidebarHeading(_ text: String) -> Widget {
        Padding(padding: EdgeInsets(left: 10, top: 0, right: 10, bottom: 6)) {
            Text(text, style: TextStyle(color: Win11.textFaint, fontSize: 11,
                                        fontWeight: .w600))
        }
    }

    private func placeRow(_ place: Win32Place) -> Widget {
        let selected = bloc.state.directory == place.path
        return GestureDetector(
            onTap: { self.bloc.add(.open(place.path)) },
            child: Padding(padding: EdgeInsets(left: 0, top: 1, right: 0, bottom: 1)) {
                ClipRRect(borderRadius: BorderRadius.circular(6)) {
                    ColoredBox(color: selected ? Color(0x2E6FA8FF) : Color(0x00000000)) {
                        SizedBox(height: 30) {
                            Padding(padding: EdgeInsets(horizontal: 10, vertical: 0)) {
                                Row(crossAxisAlignment: .center, spacing: 9) {
                                    MacosIcon(icon: CupertinoIcons.folder_fill,
                                              color: Color(0xFF7FA9DE), size: 14)
                                    Text(place.name,
                                         style: TextStyle(color: Color(0xFFE6EAF0),
                                                          fontSize: 13),
                                         maxLines: 1)
                                }
                            }
                        }
                    }
                }
            })
    }

    // MARK: - Toolbar

    // MARK: - Explorer's chrome
    //
    // Three stacked bars and a header strip, in Windows 11's order: tabs,
    // command bar, breadcrumb-and-search, columns.

    /// The tab strip. ONE tab, showing where we are -- tabs proper need a
    /// window that can hold several listings and this holds one, so a strip
    /// that pretended otherwise would be chrome that does nothing. The shape
    /// is Explorer's; the count is honest.
    private func tabStrip() -> Widget {
        SizedBox(height: kFilesTabStrip) {
            Padding(padding: EdgeInsets(left: 8, top: 6, right: 8, bottom: 0)) {
                Row(crossAxisAlignment: .stretch) {
                    ClipRRect(borderRadius: BorderRadius.circular(6)) {
                        ColoredBox(color: Win11.surface) {
                            Padding(padding: EdgeInsets(horizontal: 12, vertical: 0)) {
                                Row(crossAxisAlignment: .center, spacing: 8) {
                                    MacosIcon(icon: CupertinoIcons.folder_fill,
                                              color: Win11.textDim, size: 13)
                                    Text(folderLabel(),
                                         style: TextStyle(color: Win11.text, fontSize: 12),
                                         maxLines: 1)
                                }
                            }
                        }
                    }
                    Expanded { SizedBox(height: 1) }
                }
            }
        }
    }

    /// The command bar. Everything on it that needs IFileOperation is drawn
    /// disabled -- see this file's header.
    private func commandBar() -> Widget {
        SizedBox(height: kFilesCommandBar) {
            Padding(padding: EdgeInsets(left: 10, top: 0, right: 10, bottom: 0)) {
                Row(crossAxisAlignment: .center, spacing: 2) {
                    barButton(CupertinoIcons.add, "New", enabled: false) {}
                    barSeparator()
                    barIcon(CupertinoIcons.scissors, enabled: false) {}
                    barIcon(CupertinoIcons.doc_on_doc, enabled: false) {}
                    barIcon(CupertinoIcons.doc_on_clipboard, enabled: false) {}
                    barIcon(CupertinoIcons.pencil, enabled: false) {}
                    barIcon(CupertinoIcons.trash, enabled: false) {}
                    barSeparator()
                    barButton(CupertinoIcons.arrow_up_arrow_down, sortLabel(), enabled: true) {
                        self.cycleSort()
                    }
                    barButton(CupertinoIcons.square_grid_2x2, "View", enabled: false) {}
                    Expanded { SizedBox(height: 1) }
                    textButton("Open in Explorer") { self.bloc.add(.openInExplorer) }
                }
            }
        }
    }

    /// Back, forward, up, refresh, the breadcrumb, and search.
    private func navigationBar() -> Widget {
        SizedBox(height: kFilesNavBar) {
            Padding(padding: EdgeInsets(left: 10, top: 0, right: 10, bottom: 6)) {
                Row(crossAxisAlignment: .center, spacing: 4) {
                    navIcon(CupertinoIcons.chevron_left, enabled: bloc.canGoBack) {
                        self.bloc.add(.goBack)
                    }
                    navIcon(CupertinoIcons.chevron_right, enabled: bloc.canGoForward) {
                        self.bloc.add(.goForward)
                    }
                    navIcon(CupertinoIcons.chevron_up, enabled: bloc.state.canGoUp) {
                        self.bloc.add(.goUp)
                    }
                    navIcon(CupertinoIcons.arrow_clockwise, enabled: true) {
                        self.bloc.add(.refresh)
                    }
                    SizedBox(width: 4)
                    Expanded { breadcrumb() }
                    SizedBox(width: 8)
                    searchBox()
                }
            }
        }
    }

    /// The address bar, as Explorer draws it: the path broken into segments
    /// with chevrons between them, each one a place you can go back to.
    private func breadcrumb() -> Widget {
        let parts = crumbs()
        return ClipRRect(borderRadius: BorderRadius.circular(4)) {
            ColoredBox(color: Win11.fieldFill) {
                SizedBox(height: 32) {
                    Padding(padding: EdgeInsets(horizontal: 10, vertical: 0)) {
                        Row(crossAxisAlignment: .center, spacing: 2) {
                            for (i, crumb) in parts.enumerated() {
                                if i > 0 {
                                    MacosIcon(icon: CupertinoIcons.chevron_right,
                                              color: Win11.textFaint, size: 9)
                                }
                                GestureDetector(
                                    onTap: { self.bloc.add(.open(crumb.path)) },
                                    child: Padding(
                                        padding: EdgeInsets(horizontal: 5, vertical: 3)) {
                                        Text(crumb.label,
                                             style: TextStyle(
                                                color: i == parts.count - 1
                                                    ? Win11.text : Win11.textDim,
                                                fontSize: 12),
                                             maxLines: 1)
                                    })
                            }
                            Expanded { SizedBox(height: 1) }
                        }
                    }
                }
            }
        }
    }

    /// Filters the listing already in memory. NOT Explorer's search, which
    /// walks the subtree and asks the index -- this is the current folder, and
    /// the placeholder says so, because a search box that quietly searches
    /// less than the user expects is worse than one that never ran.
    private func searchBox() -> Widget {
        SizedBox(width: 220, height: 32) {
            MacosTextField(
                controller: search,
                placeholder: "Search this folder",
                prefix: Padding(padding: EdgeInsets(left: 6, top: 0, right: 0, bottom: 0)) {
                    MacosIcon(icon: CupertinoIcons.search, color: Win11.textFaint, size: 12)
                },
                onChanged: { text in self.bloc.add(.filter(text)) },
                style: TextStyle(color: Win11.text, fontSize: 12),
                padding: EdgeInsets(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                    color: Win11.fieldFill,
                    border: Border.all(color: Win11.stroke, width: 1),
                    borderRadius: BorderRadius.circular(4)))
        }
    }

    /// Name / Date modified / Type / Size, and a click sorts by one.
    private func columnHeaders() -> Widget {
        SizedBox(height: kFilesHeaderRow) {
            ColoredBox(color: Win11.listBg) {
                Padding(padding: EdgeInsets(left: 16, top: 0, right: 16, bottom: 0)) {
                    Row(crossAxisAlignment: .center, spacing: 10) {
                        SizedBox(width: 18, height: 1)
                        Expanded { headerCell("Name", .name, true) }
                        SizedBox(width: kFilesColModified) {
                            headerCell("Date modified", .modified, false)
                        }
                        SizedBox(width: kFilesColType) { headerCell("Type", .type, true) }
                        SizedBox(width: kFilesColSize) { headerCell("Size", .size, false) }
                    }
                }
            }
        }
    }

    private func headerCell(_ title: String, _ key: FilesSortKey,
                            _ leading: Bool) -> Widget {
        let active = bloc.state.sortKey == key
        return GestureDetector(
            onTap: { self.bloc.add(.sort(key)) },
            child: Align(alignment: leading ? Alignment.centerLeft
                                            : Alignment.centerRight) {
                Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 4) {
                    Text(title,
                         style: TextStyle(color: active ? Win11.text : Win11.textFaint,
                                          fontSize: 11),
                         maxLines: 1)
                    // The arrow is the only thing that says which way a
                    // re-click will flip it.
                    if active {
                        MacosIcon(icon: bloc.state.sortAscending
                                      ? CupertinoIcons.chevron_up
                                      : CupertinoIcons.chevron_down,
                                  color: Win11.accent, size: 8)
                    }
                }
            })
    }

    /// Explorer's status bar: how many things are here, and what is picked.
    ///
    /// This ALSO carries what used to be a second bar of its own -- the
    /// description of what will open the selected file, and the two buttons
    /// that do it. Explorer has no such bar, but the question it answers
    /// ("what happens if I double-click this") is a real one, and two stacked
    /// bars both reporting the item count was worse than either.
    private func statusBar() -> Widget {
        let entry = bloc.state.visible.first { $0.path == bloc.state.selected }
        return SizedBox(height: kFilesStatusBar) {
            ColoredBox(color: Win11.windowBg) {
                Padding(padding: EdgeInsets(left: 14, top: 0, right: 10, bottom: 0)) {
                    Row(crossAxisAlignment: .center, spacing: 12) {
                        Text(itemCountLabel(),
                             style: TextStyle(color: Win11.textFaint, fontSize: 11),
                             maxLines: 1)
                        if entry != nil {
                            Text("1 item selected",
                                 style: TextStyle(color: Win11.textFaint, fontSize: 11),
                                 maxLines: 1)
                        }
                        Expanded {
                            Align(alignment: Alignment.centerRight) {
                                Text(footerText(entry),
                                     style: TextStyle(color: Win11.textFaint, fontSize: 11),
                                     maxLines: 1)
                            }
                        }
                        if let entry, !entry.isDirectory {
                            textButton("Open") { self.bloc.add(.activate(entry)) }
                            textButton("Open with\u{2026}") { self.bloc.add(.openWith) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Chrome pieces

    private func barSeparator() -> Widget {
        Padding(padding: EdgeInsets(horizontal: 4, vertical: 10)) {
            SizedBox(width: 1) { ColoredBox(color: Win11.stroke) { SizedBox(width: 1) } }
        }
    }

    private func barIcon(_ icon: IconData, enabled: Bool,
                         _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: enabled ? action : {},
            child: SizedBox(width: 34, height: 30) {
                Center {
                    MacosIcon(icon: icon,
                              color: enabled ? Win11.textDim : Win11.disabled,
                              size: 14)
                }
            })
    }

    private func barButton(_ icon: IconData, _ label: String, enabled: Bool,
                           _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: enabled ? action : {},
            child: SizedBox(height: 30) {
                Padding(padding: EdgeInsets(horizontal: 9, vertical: 0)) {
                    Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 6) {
                        MacosIcon(icon: icon,
                                  color: enabled ? Win11.textDim : Win11.disabled,
                                  size: 13)
                        Text(label,
                             style: TextStyle(
                                color: enabled ? Win11.textDim : Win11.disabled,
                                fontSize: 12))
                    }
                }
            })
    }

    private func navIcon(_ icon: IconData, enabled: Bool,
                         _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: enabled ? action : {},
            child: SizedBox(width: 32, height: 32) {
                Center {
                    MacosIcon(icon: icon,
                              color: enabled ? Win11.textDim : Win11.disabled,
                              size: 13)
                }
            })
    }

    // MARK: - Labels

    /// The tab's caption: the folder's own name, or the drive when we are at
    /// the root of one and there is no name to take.
    private func folderLabel() -> String {
        let path = bloc.state.directory
        if path.isEmpty { return "Files" }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    private func crumbs() -> [(label: String, path: String)] {
        let path = bloc.state.directory
        guard !path.isEmpty else { return [] }
        var out: [(label: String, path: String)] = []
        var walk: String? = path
        while let here = walk, !here.isEmpty {
            let name = (here as NSString).lastPathComponent
            out.append((label: name.isEmpty ? here : name, path: here))
            walk = Win32Files.parent(of: here)
        }
        return out.reversed()
    }

    private func itemCountLabel() -> String {
        let shown = bloc.state.visible.count
        let total = bloc.state.entries.count
        if !bloc.state.filter.isEmpty { return "\(shown) of \(total) items" }
        return total == 1 ? "1 item" : "\(total) items"
    }

    private func sortLabel() -> String {
        switch bloc.state.sortKey {
        case .name: return "Sort: Name"
        case .modified: return "Sort: Date"
        case .type: return "Sort: Type"
        case .size: return "Sort: Size"
        }
    }

    /// The command bar's Sort button walks the four columns, so the control is
    /// reachable without going to the header row.
    private func cycleSort() {
        switch bloc.state.sortKey {
        case .name: bloc.add(.sort(.modified))
        case .modified: bloc.add(.sort(.type))
        case .type: bloc.add(.sort(.size))
        case .size: bloc.add(.sort(.name))
        }
    }

    private func textButton(_ text: String, _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: action,
            child: ClipRRect(borderRadius: BorderRadius.circular(6)) {
                ColoredBox(color: Color(0x1AFFFFFF)) {
                    SizedBox(height: 28) {
                        Padding(padding: EdgeInsets(horizontal: 12, vertical: 0)) {
                            Center {
                                Text(text, style: TextStyle(color: Color(0xFFD5DAE3),
                                                            fontSize: 12))
                            }
                        }
                    }
                }
            })
    }

    // MARK: - Footer
    //
    // What opens the selected file, and the two things you can do about it.
    //
    // A footer rather than a right-click menu on purpose: widget-level
    // secondary taps are not reliable in this framework, and a bar that is
    // always visible also answers a question the user did not know to ask —
    // "what will happen if I open this" — before they double-click.

    /// What the status bar says about the SELECTION, and nothing when there is
    /// none: the item count lives at the other end of the same bar now, and
    /// this returning it too is what put it on screen twice.
    private func footerText(_ entry: Win32FileEntry?) -> String {
        guard let entry else { return "" }
        if entry.isDirectory { return entry.name }
        let type = bloc.state.selectedType ?? ""
        // "Opens with" is the honest phrasing: it is what WOULD happen, and
        // the app cannot change it — only the shell's dialog can.
        if let app = bloc.state.selectedApp {
            return type.isEmpty ? "\(entry.name)  ·  opens with \(app)"
                                : "\(entry.name)  ·  \(type)  ·  opens with \(app)"
        }
        return type.isEmpty ? entry.name
                            : "\(entry.name)  ·  \(type)  ·  nothing opens this yet"
    }

    // MARK: - Listing

    private func listing() -> Widget {
        if let error = bloc.state.error { return message(error) }
        if bloc.state.loading && bloc.state.entries.isEmpty {
            return Column(mainAxisAlignment: .center, crossAxisAlignment: .center) {
                SizedBox(width: 240) { MacosProgressIndicator() }
                SizedBox(height: 12)
                Text("Reading the folder",
                     style: TextStyle(color: Color(0xFF6E7683), fontSize: 13))
            }
        }
        if bloc.state.entries.isEmpty { return message("This folder is empty.") }
        if bloc.state.visible.isEmpty {
            return message("No items match \"\(bloc.state.filter)\".")
        }

        // Lazy: a folder of ten thousand files builds only the rows on screen.
        return ListView(
            controller: scroll,
            itemExtent: kFilesRow,
            itemCount: bloc.state.visible.count,
            itemBuilder: { [weak self] _, index in self?.row(index) })
    }

    private func message(_ text: String) -> Widget {
        Column(mainAxisAlignment: .center, crossAxisAlignment: .center) {
            Text(text, style: TextStyle(color: Color(0xFF6E7683), fontSize: 13))
        }
    }

    private func row(_ index: Int) -> Widget {
        guard index < bloc.state.visible.count else { return SizedBox(height: kFilesRow) }
        let entry = bloc.state.visible[index]
        let selected = bloc.state.selected == entry.path
        let key = FilesBloc.iconKey(entry)

        return GestureDetector(
            onTap: { self.tapped(entry) },
            child: ColoredBox(color: selected ? Win11.selection : Color(0x00000000)) {
                SizedBox(height: kFilesRow) {
                    Padding(padding: EdgeInsets(left: 16, top: 0, right: 16, bottom: 0)) {
                        Row(crossAxisAlignment: .center, spacing: 10) {
                            SizedBox(width: 18, height: 18) {
                                Center {
                                    if let icon = bloc.icons.view(key, side: 16) {
                                        icon
                                    } else {
                                        MacosIcon(icon: entry.isDirectory
                                                      ? CupertinoIcons.folder_fill
                                                      : CupertinoIcons.doc,
                                                  color: Win11.textFaint, size: 14)
                                    }
                                }
                            }
                            Expanded {
                                Text(entry.name,
                                     style: TextStyle(color: Win11.text, fontSize: 12),
                                     maxLines: 1)
                            }
                            SizedBox(width: kFilesColModified) {
                                Align(alignment: Alignment.centerRight) {
                                    Text(modifiedText(entry),
                                         style: TextStyle(color: Win11.textFaint,
                                                          fontSize: 12),
                                         maxLines: 1)
                                }
                            }
                            // Cached by extension -- a per-row registry walk
                            // is what the selection footer exists to avoid.
                            SizedBox(width: kFilesColType) {
                                Align(alignment: Alignment.centerLeft) {
                                    Text(FilesBloc.typeLabel(entry),
                                         style: TextStyle(color: Win11.textFaint,
                                                          fontSize: 12),
                                         maxLines: 1)
                                }
                            }
                            SizedBox(width: kFilesColSize) {
                                Align(alignment: Alignment.centerRight) {
                                    Text(entry.isDirectory ? "" : sizeText(entry.size),
                                         style: TextStyle(color: Win11.textFaint,
                                                          fontSize: 12),
                                         maxLines: 1)
                                }
                            }
                        }
                    }
                }
            })
    }

    /// Select on the first tap, open on a second within half a second. See
    /// `lastTapPath` for why this is not `onDoubleTap`.
    private func tapped(_ entry: Win32FileEntry) {
        let now = Date()
        let again = lastTapPath == entry.path
            && now.timeIntervalSince(lastTapAt) < 0.5
        lastTapPath = entry.path
        lastTapAt = now
        if again {
            lastTapPath = nil
            bloc.add(.activate(entry))
        } else {
            bloc.add(.select(entry.path))
        }
    }

    private func sizeText(_ bytes: Int64) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
        }
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
        if bytes >= 1024 { return "\(bytes / 1024) KB" }
        return "\(bytes) B"
    }

    private func modifiedText(_ entry: Win32FileEntry) -> String {
        guard let date = entry.modified else { return "" }
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy  HH:mm"
        return f.string(from: date)
    }
}
#endif
