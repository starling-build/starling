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
import FlutterWin32Bridge
import Foundation

let kLauncherIcon = 56.0
let kLauncherCell = 132.0
/// Points kept clear at the left and right of the grid, so the outermost
/// column is not flush against the screen edge.
let kLauncherMargin = 80.0

/// Everything the launcher needs, prepared while nobody is waiting for it.
///
/// This exists because the obvious place to do it -- the state's `initState`
/// -- turned out not to run until the launcher was first SHOWN, which is the
/// one moment it must not be doing 500ms of work.
///
/// The overlay parks as a 1x1 window rather than hiding, on the theory that a
/// window which is genuinely on screen keeps being sent frames, so the tree
/// mounts at startup and stands ready. Measured on a real GPU, that is not
/// what happens: a launcher parked for 54 SECONDS had still never built its
/// tree, and `initState` ran for the first time on the toggle -- 158ms
/// walking the Start Menu through COM and 354ms rasterizing 79 icons, with
/// the user watching a blank screen for every millisecond of it. (In a
/// session with no GPU, where everything falls back to software, it does
/// mount at startup, which is how the theory survived this long.)
///
/// So the work is hung off PROCESS start instead of off the widget lifecycle,
/// where it does not depend on anything being composited:
///
///   - the catalog on its own thread, because it is pure Win32 and COM is
///     initialized per call, so its ~158ms overlaps engine creation and costs
///     nothing at all;
///   - the icons on the main queue, which the host drains from its message
///     loop, because registering a texture needs the engine to exist.
///
/// The tree still mounts on first show. It just has nothing left to do by
/// then except lay out and paint.
final class LauncherPreload {
    static let shared = LauncherPreload()

    let icons = IconCache()
    private let lock = NSLock()
    private var loadedApps: [Win32App] = []
    private var loaded = false

    /// Called on the main thread when the catalog lands, so a launcher that
    /// mounted first stops showing its loading state. Usually the catalog wins
    /// the race — it finishes around 200ms and the tree mounts around 340ms —
    /// but "usually" is not something to leave a permanent spinner on.
    var onCatalogReady: (() -> Void)?

    /// Whether the Start Menu walk has finished. The UI shows a loading state
    /// until it has, rather than an empty grid or a blocked thread.
    var catalogReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return loaded
    }

    var apps: [Win32App] {
        lock.lock()
        defer { lock.unlock() }
        return loadedApps
    }

    /// Call once, before `runStarlingApp`.
    func begin() {
        flwin32_trace("preload: catalog thread starting")
        Thread.detachNewThread {
            let found = Win32AppCatalog.apps()
            self.lock.lock()
            self.loadedApps = found
            self.loaded = true
            self.lock.unlock()
            flwin32_trace("preload: catalog done (background)")
            DispatchQueue.main.async { self.onCatalogReady?() }
        }
        DispatchQueue.main.async { self.warmIcons() }
    }

    /// Rasterize and register every icon up front. Re-queues itself if the
    /// catalog thread has not finished: the message loop starts about 330ms
    /// in and the catalog takes about 158ms, so this is nearly always ready
    /// on the first attempt -- but "nearly" is not a thing to build on.
    private func warmIcons() {
        lock.lock()
        let ready = loaded
        let list = loadedApps
        lock.unlock()
        guard ready else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { self.warmIcons() }
            return
        }
        for app in list { icons.ensure(app: app, size: 64) }
        flwin32_trace("preload: icons dispatched")
    }
}

final class StarlingLauncher: StatefulWidget {
    override func createState() -> State<StatefulWidget> { StarlingLauncherState() }
}

final class StarlingLauncherState: State<StatefulWidget> {
    private let icons = LauncherPreload.shared.icons
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
        flwin32_trace("launcher initState: begin")
        CupertinoIcons.registerFont()
        // Both of these were built here and are now built at process start;
        // see LauncherPreload for what that cost when it happened on the
        // first keypress instead.
        apps = LauncherPreload.shared.apps
        // Icons are rasterized off the UI thread, so they land AFTER this
        // build. Without this the grid keeps whatever it drew first — which
        // is the fallback glyph for every icon that was not ready yet, and
        // that is most of them.
        icons.onTextureReady = { [weak self] in
            guard let self else { return }
            setState {}
        }
        LauncherPreload.shared.onCatalogReady = { [weak self] in
            guard let self else { return }
            setState { self.apps = LauncherPreload.shared.apps }
        }
        print("[WinShellLauncher] \(apps.count) apps")
        // The icons are already rasterized and registered — LauncherPreload
        // did it at process start. This catches anything installed since.
        for app in apps { icons.ensure(app: app, size: 64) }
        flwin32_trace("launcher initState: done")

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
        // NOT icons.releaseAll(): the cache belongs to LauncherPreload and
        // outlives this state, so releasing here would throw away the very
        // thing that was prepared at startup.
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
        flwin32_trace("launcher: launch tapped")
        // HIDE FIRST. Starting an app is not instant even on the fast path,
        // and it is a synchronous shell call on this thread — so launching
        // first left the launcher sitting on screen, frozen, until it
        // returned. Getting out of the way is the part the user is waiting
        // for; the app arriving is the part they expect to take a moment.
        Win32WindowedHost.host?.setVisible(false)
        flwin32_trace("launcher: hidden")
        // Off the UI thread: the fast path is 8ms but the `.lnk` fallback
        // measured 484ms, and this thread has frames to draw.
        StarlingDockState.launchOffThread(app)
        flwin32_trace("launcher: launch dispatched")
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
        max(1, Int((ShellScreen.logicalHeight - 210) / kLauncherCell))
    }

    /// And how many columns, for the same reason from the other direction.
    ///
    /// This was a fixed seven, which fits a 1024pt screen by luck. On the
    /// 3840x2160 laptop panel at 200% — 1920pt logical — seven columns is a
    /// 924pt island of icons with five hundred points of dead space either
    /// side of it, and the pager insisting there are more pages of apps that
    /// the screen plainly has room for.
    private var columnsPerPage: Int {
        max(1, Int((ShellScreen.logicalWidth - kLauncherMargin) / kLauncherCell))
    }

    private var perPage: Int { columnsPerPage * rowsPerPage }

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
        // Rechecked here, and read ONCE: every row has to be cut to the same
        // width, so a monitor changing between the first row and the last
        // would otherwise give a ragged grid.
        ShellScreen.refresh()
        let columns = columnsPerPage
        let start = min(page * perPage, max(0, list.count - 1))
        let end = min(start + perPage, list.count)
        var rows: [Widget] = []
        var index = start
        while index < end {
            let row = Array(list[index..<min(index + columns, end)])
            rows.append(Row(mainAxisAlignment: .center, mainAxisSize: .min,
                            children: row.map { tile($0) }))
            index += columns
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

    /// Shown while the Start Menu walk is still running on its own thread.
    private func loading() -> Widget {
        SizedBox(height: Double(rowsPerPage) * kLauncherCell) {
            Column(mainAxisAlignment: .center, crossAxisAlignment: .center) {
                SizedBox(width: 240) {
                    MacosProgressIndicator()
                }
                SizedBox(height: 18)
                Text("Reading the Start Menu",
                     style: TextStyle(color: Color(0xFF6E7683), fontSize: 13))
            }
        }
    }

    private var tracedFirstBuild = false

    override func build(_ context: any BuildContext) -> Widget {
        if !tracedFirstBuild {
            tracedFirstBuild = true
            flwin32_trace("launcher: first build()")
        }
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
                    // Nothing to show YET is different from nothing to show.
                    //
                    // The catalog is read off the UI thread, so there is a
                    // window — small, but real on a cold machine — where the
                    // launcher is up and the Start Menu walk has not finished.
                    // An empty grid reads as "you have no apps"; this reads as
                    // what it is. The alternative, blocking until the catalog
                    // is ready, is the thing this whole change exists to stop.
                    if !LauncherPreload.shared.catalogReady {
                        loading()
                    } else {
                        grid(list)
                    }
                    SizedBox(height: 24)
                    // Tap targets as well as the wheel: a page you can only
                    // reach by scrolling is a page most people never find,
                    // and taps are the one pointer route this framework
                    // delivers without argument.
                    Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 14) {
                        if pageCount > 1 { pageButton("‹", to: page - 1) }
                        Text(!LauncherPreload.shared.catalogReady ? "Loading apps"
                                : list.isEmpty ? "No apps match \"\(query)\""
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
