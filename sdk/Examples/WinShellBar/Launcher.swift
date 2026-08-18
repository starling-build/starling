// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The launcher: everything installed, in a grid, over the whole screen.
//
// Starling's Launchpad, on Windows, over the same Start Menu catalog the dock
// reads. It is the first surface here that is an OVERLAY rather than a panel —
// it covers the monitor, reserves nothing, takes the keyboard, and spends most
// of its life hidden rather than not running, because starting an engine costs
// about a second and a launcher has to be there the instant it is asked for.
//
// The bar's Starling button is what asks. They are separate processes, so the
// ask is a broadcast of a registered window message (see `Win32Shell`).

#if os(Windows)
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import Foundation

let kLauncherColumns = 7
let kLauncherIcon = 56.0
let kLauncherCell = 132.0

final class StarlingLauncher: StatefulWidget {
    override func createState() -> State<StatefulWidget> { StarlingLauncherState() }
}

final class StarlingLauncherState: State<StatefulWidget> {
    private let icons = IconCache()
    private var apps: [Win32App] = []
    private var query = ""
    private let search = TextEditingController()
    /// Which page of the grid is showing. The grid is a fixed number of rows
    /// — six — and everything past that used to simply not exist, so on a
    /// machine with three hundred apps you could only reach the first
    /// forty-two without typing.
    private var page = 0

    override func initState() {
        super.initState()
        CupertinoIcons.registerFont()
        apps = Win32AppCatalog.apps()
        print("[WinShellLauncher] \(apps.count) apps")
        // Every icon up front. A few hundred rasterizations is a second of
        // work, and it happens while nobody is looking — which is the whole
        // reason this process starts hidden instead of on demand.
        for app in apps { icons.ensure(app: app, size: 64) }

        // A notification, not a request: the HOST does the showing, because
        // while this overlay is hidden there is no tree to ask — a hidden
        // window is never sent a frame, and the tree only builds on the first
        // frame request, so none of this code has run yet at that point. By
        // the time this fires we are already on screen.
        Win32WindowedHost.host?.onToggle { [weak self] in
            self?.didToggle()
        }
    }

    override func dispose() {
        icons.releaseAll()
        super.dispose()
    }

    // MARK: - Showing and hiding

    private func didToggle() {
        guard Win32WindowedHost.host?.isVisible == true else { return }
        // Always open on an empty query: a launcher that remembers the last
        // search is a launcher that shows you the wrong four apps every time
        // you open it.
        setState {
            self.query = ""
            self.search.text = ""
            self.page = 0
        }
    }

    private func launch(_ app: Win32App) {
        Win32AppCatalog.launch(app)
        Win32WindowedHost.host?.setVisible(false)
    }

    // MARK: - Model

    /// Substring match on the name, which is what a Start Menu search does.
    /// Entries whose name STARTS with the query sort first, so typing "no"
    /// puts Notepad above Norton Notifier rather than wherever the alphabet
    /// left it.
    /// How many rows fit, worked out from the screen rather than fixed.
    ///
    /// Six rows is 792pt of tiles, which is taller than a 768pt screen — the
    /// bottom of the grid simply fell off, and because the page size was the
    /// same constant, paging never triggered to reveal it either. Deriving
    /// both from the height fixes the overflow and makes the paging real.
    private var rowsPerPage: Int {
        let height = Double(Win32Display.primary()?.logicalHeight ?? 800)
        return max(1, Int((height - 210) / kLauncherCell))
    }

    private var perPage: Int { kLauncherColumns * rowsPerPage }

    private var pageCount: Int {
        max(1, (matches.count + perPage - 1) / perPage)
    }

    private var matches: [Win32App] {
        guard !query.isEmpty else { return apps }
        let needle = query.lowercased()
        let hits = apps.filter { $0.name.lowercased().contains(needle) }
        return hits.sorted { a, b in
            let aStarts = a.name.lowercased().hasPrefix(needle)
            let bStarts = b.name.lowercased().hasPrefix(needle)
            if aStarts != bStarts { return aStarts }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Build

    private func tile(_ app: Win32App) -> Widget {
        GestureDetector(
            onTap: { self.launch(app) },
            child: SizedBox(width: kLauncherCell, height: kLauncherCell) {
                Column(mainAxisAlignment: .center, crossAxisAlignment: .center) {
                    if let icon = icons.view(IconCache.key(for: app), side: kLauncherIcon) {
                        icon
                    } else {
                        SizedBox(width: kLauncherIcon, height: kLauncherIcon) {
                            Center {
                                MacosIcon(icon: CupertinoIcons.app_badge,
                                          color: Color(0xFF8E96A3), size: 34)
                            }
                        }
                    }
                    SizedBox(height: 10)
                    SizedBox(width: kLauncherCell - 12, height: 16) {
                        Text(app.name,
                             style: TextStyle(color: Color(0xFFE6EAF0), fontSize: 12),
                             textAlign: .center,
                             overflow: .ellipsis,
                             maxLines: 1)
                    }
                }
            })
    }

    /// Rows built by hand rather than by a grid widget: the tile size is
    /// fixed, so the layout is arithmetic, and this avoids a lazy sliver whose
    /// children would not rebuild when the query changes (a trap the desktop's
    /// own notes call out).
    private func grid(_ list: [Win32App]) -> Widget {
        let start = min(page * perPage, max(0, list.count - 1))
        let end = min(start + perPage, list.count)
        var rows: [Widget] = []
        var index = start
        while index < end {
            let row = Array(list[index..<min(index + kLauncherColumns, end)])
            rows.append(Row(mainAxisAlignment: .center, mainAxisSize: .min,
                            children: row.map { tile($0) }))
            index += kLauncherColumns
        }
        return Column(mainAxisSize: .min, crossAxisAlignment: .center,
                      children: rows)
    }

    private func pageButton(_ glyph: String, to wanted: Int) -> Widget {
        let enabled = wanted >= 0 && wanted < pageCount
        return GestureDetector(
            onTap: {
                guard enabled else { return }
                self.setState { self.page = wanted }
            },
            child: SizedBox(width: 26, height: 26) {
                Center {
                    Text(glyph,
                         style: TextStyle(
                            color: enabled ? Color(0xFFB0B7C3) : Color(0xFF3A4049),
                            fontSize: 18))
                }
            })
    }

    override func build(_ context: any BuildContext) -> Widget {
        let list = matches
        return Directionality(
            textDirection: .ltr,
            // Paging on the wheel, through a Listener: it is the one pointer
            // route this framework delivers reliably (MouseRegion and
            // secondary taps do not arrive — see the dock's note), and a
            // scroll view would be a lazy sliver whose children do not
            // rebuild when the query changes.
            child: Listener(
                onPointerSignal: { event in
                    guard let scroll = event as? PointerScrollEvent else { return }
                    let step = scroll.scrollDelta.dy > 0 ? 1 : -1
                    let wanted = max(0, min(self.pageCount - 1, self.page + step))
                    guard wanted != self.page else { return }
                    self.setState { self.page = wanted }
                },
                child: ColoredBox(color: Color(0xFF14161A)) {
                Column(mainAxisAlignment: .center, crossAxisAlignment: .center) {
                    SizedBox(width: 460, height: 34) {
                        MacosTextField(
                            controller: search,
                            placeholder: "Search",
                                            onChanged: { text in
                                // Back to page one on every keystroke: the
                                // results changed underneath, so the page
                                // number is about a list that no longer
                                // exists.
                                self.setState {
                                    self.query = text
                                    self.page = 0
                                }
                            },
                            onSubmitted: { _ in
                                if let first = self.matches.first { self.launch(first) }
                            })
                    }
                    SizedBox(height: 34)
                    grid(list)
                    SizedBox(height: 24)
                    // Tap targets as well as the wheel: a page you can only
                    // reach by scrolling is a page most people never find,
                    // and taps are the one pointer route this framework
                    // delivers without argument.
                    Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 14) {
                        if pageCount > 1 { pageButton("‹", to: page - 1) }
                        Text(list.isEmpty ? "No apps match \"\(query)\""
                                : pageCount > 1
                                    ? "\(list.count) apps  ·  page \(page + 1) of \(pageCount)"
                                    : "\(list.count) apps",
                             style: TextStyle(color: Color(0xFF6E7683), fontSize: 12))
                        if pageCount > 1 { pageButton("›", to: page + 1) }
                    }
                }
            }))
    }
}
#endif
