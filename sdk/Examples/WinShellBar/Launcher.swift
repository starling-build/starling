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
import Observation
import Foundation

/// The panel's size in points, and how far it floats above the dock.
///
/// A FLOATING PANEL, not a full-screen takeover. Blacking out the whole
/// display to offer a grid of icons is the macOS habit — Launchpad does it
/// because macOS has no Start button and the gesture arrives from anywhere.
/// Windows has a corner the user is already pointing at, and its own Start
/// menu is a panel above the taskbar; covering their work to show them a list
/// of programs is a bigger interruption than the task deserves.
///
/// Sized so the grid comes out at 7 columns by 5 rows — 35 apps a page, so a
/// 79-app Start Menu is three pages. 740pt is also, not by coincidence, the
/// height of Windows' own Start menu.
let kLauncherWidth = 780.0
let kLauncherHeight = 740.0
let kLauncherGap = 12.0

let kLauncherIcon = 48.0
let kLauncherCell = 104.0
/// Points kept clear at the left and right of the grid, so the outermost
/// column is not flush against the panel's edge.
let kLauncherMargin = 48.0

/// The power menu's row height and width, shared by the drawing and the
/// arithmetic hit test.
let kPowerRowH = 38.0
let kPowerMenuW = 190.0

/// The single source of truth for the launcher.
struct LauncherState {
    /// Everything installed, from the Start Menu.
    var apps: [Win32App] = []
    /// Whether the walk has finished. Until it has the UI says so, rather
    /// than showing an empty grid that reads as "you have no apps".
    var catalogReady = false
    /// The search box's text.
    var query = ""
    /// Which page of the grid is showing.
    var page = 0
    /// Bumped when an icon texture lands — see DockState.iconRevision.
    var iconRevision = 0
}

/// The launcher's state, and everything slow that produces it.
///
/// Same shape as the dock's — see DockBloc for the reasoning. What is specific
/// here is WHEN the work happens: the obvious home for it, the state's
/// `initState`, does not run until the launcher is first SHOWN, because a
/// parked overlay is not sent frames and this framework builds its tree on the
/// first frame request. Measured, that meant 158ms of Start Menu walking and
/// 354ms of icon rasterizing on the keypress that asked for the launcher.
///
/// So it hangs off PROCESS start instead — `add(.start)` from main.swift —
/// where nothing is waiting on it.
@Observable
final class LauncherBloc: @unchecked Sendable {

    enum Event {
        /// Begin loading. Sent from main.swift, before the tree exists.
        case start
        case search(String)
        case goToPage(Int)
        case launch(Win32App)
        /// The launcher was just shown: open on a clean query.
        case opened

        // Completions.
        case catalogLoaded([Win32App])
        case iconsChanged
    }

    private(set) var state = LauncherState()

    @ObservationIgnored let icons = IconCache()

    func add(_ event: Event) {
        switch event {
        case .start:
            _start()
        case .search(let text):
            state.query = text
            // Back to page one on every keystroke: the results changed
            // underneath, so the page number is about a list that no longer
            // exists.
            state.page = 0
        case .goToPage(let page):
            state.page = page
        case .opened:
            // Always open on an empty query: a launcher that remembers the
            // last search is one that shows you the wrong four apps every
            // time you open it.
            state.query = ""
            state.page = 0
        case .launch(let app):
            // Off the UI thread: the fast path is 8ms but the `.lnk` fallback
            // measured 484ms, and this thread has frames to draw.
            Task.detached { Win32AppCatalog.launch(app) }
        case .catalogLoaded(let apps):
            state.apps = apps
            state.catalogReady = true
            print("[WinShellLauncher] \(apps.count) apps")
            _warmIcons(apps)
        case .iconsChanged:
            state.iconRevision &+= 1
        }
    }

    private func _start() {
        icons.onTextureReady = { [weak self] in self?.add(.iconsChanged) }
        // Its own thread, because COM is initialized per call in
        // flwin32_apps.c and this overlaps engine creation, so its ~175ms
        // costs nothing at all.
        Task.detached { [weak self] in
            let apps = Win32AppCatalog.apps()
            await MainActor.run { self?.add(.catalogLoaded(apps)) }
        }
    }

    /// Rasterize every icon up front. They go through IconCache's own serial
    /// queue — asking the shell for a few hundred icons at once makes it
    /// refuse some of them.
    private func _warmIcons(_ apps: [Win32App]) {
        for app in apps { icons.ensure(app: app, size: 64) }
    }
}

/// The launcher's bloc. One surface per process, so one instance.
let launcherBloc = LauncherBloc()

final class StarlingLauncher: StatefulWidget {
    override func createState() -> State<StatefulWidget> { StarlingLauncherState() }
}

final class StarlingLauncherState: State<StatefulWidget> {
    private let bloc = launcherBloc
    /// View state: the text field's own controller. Everything else the
    /// launcher draws comes from `bloc.state`.
    private let search = TextEditingController()
    /// Whether the power menu is down. View state: it is about this pointer,
    /// not about the machine.
    private var powerOpen = false

    override func initState() {
        super.initState()
        CupertinoIcons.registerFont()

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
        // NOT icons.releaseAll(): the cache belongs to the bloc and outlives
        // this state, so releasing here would throw away the very thing that
        // was prepared at process start.
        super.dispose()
    }

    // MARK: - Showing and hiding

    private func didToggle() {
        guard Win32WindowedHost.host?.isVisible == true else { return }
        search.text = ""
        bloc.add(.opened)
    }

    private func launch(_ app: Win32App) {
        // HIDE FIRST. Starting an app is not instant even on the fast path,
        // and it is a synchronous shell call on this thread — so launching
        // first left the launcher sitting on screen, frozen, until it
        // returned. Getting out of the way is the part the user is waiting
        // for; the app arriving is the part they expect to take a moment.
        // HIDE FIRST. Getting out of the way is the part the user is waiting
        // for; the app arriving is the part they expect to take a moment.
        Win32WindowedHost.host?.setVisible(false)
        bloc.add(.launch(app))
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
    /// Against the PANEL, not the screen.
    ///
    /// These read `ShellScreen` when the launcher covered the monitor, which
    /// was right then and is wrong now: the panel is a fixed size, so the grid
    /// is the same on every display and there is nothing to re-derive when one
    /// changes. 210pt is the search field, the gaps around it and the pager.
    private var rowsPerPage: Int {
        max(1, Int((kLauncherHeight - 210) / kLauncherCell))
    }

    /// And how many columns, for the same reason from the other direction.
    ///
    /// This was a fixed seven, which fits a 1024pt screen by luck. On the
    /// 3840x2160 laptop panel at 200% — 1920pt logical — seven columns is a
    /// 924pt island of icons with five hundred points of dead space either
    /// side of it, and the pager insisting there are more pages of apps that
    /// the screen plainly has room for.
    private var columnsPerPage: Int {
        max(1, Int((kLauncherWidth - kLauncherMargin) / kLauncherCell))
    }

    private var perPage: Int { columnsPerPage * rowsPerPage }

    private var pageCount: Int {
        max(1, (matches.count + perPage - 1) / perPage)
    }

    private var matches: [Win32App] {
        guard !bloc.state.query.isEmpty else { return bloc.state.apps }
        let needle = bloc.state.query.lowercased()
        let hits = bloc.state.apps.filter { $0.name.lowercased().contains(needle) }
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
                    if let icon = bloc.icons.view(IconCache.key(for: app), side: kLauncherIcon) {
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
        let start = min(bloc.state.page * perPage, max(0, list.count - 1))
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
                self.bloc.add(.goToPage(wanted))
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

    // MARK: - Power
    //
    // Hit-tested ARITHMETICALLY from the root Listener, not by the
    // GestureDetector the button is drawn with. A GestureDetector works for
    // the app tiles, which sit in the grid's Column — it does NOT fire for a
    // `Positioned` child of a `Stack` in this framework, and the failure is
    // silent: the button draws, the press lands nowhere, and nothing happens.
    // The dock reached the same conclusion for the same reason and drives its
    // whole surface from one Listener.
    //
    // Both rectangles come from here so the drawing and the hit test cannot
    // drift apart.




    private func choosePower(_ action: Win32Session.Action) {
        setState { powerOpen = false }
        // Out of the way first: whatever happens next, the launcher should not
        // be the last thing on screen during it.
        Win32WindowedHost.host?.setVisible(false)
        Task.detached { Win32Session.perform(action) }
    }

    /// The power button, bottom-right, where Windows' own Start menu puts it.
    ///
    /// It opens a MENU rather than doing anything. That is not politeness, it
    /// is the confirmation: a single click that ends the session — with
    /// whatever is unsaved in whatever is open — is not something to put one
    /// pointer-slip away from the app grid.
    private func powerButton() -> Widget {
        GestureDetector(
            onTap: { self.setState { self.powerOpen.toggle() } },
            child: SizedBox(width: 40, height: 40) {
                Center {
                    ClipRRect(borderRadius: BorderRadius.circular(20)) {
                        ColoredBox(color: powerOpen ? Color(0x22FFFFFF)
                                                    : Color(0x00000000)) {
                            SizedBox(width: 40, height: 40) {
                                Center {
                                    MacosIcon(icon: CupertinoIcons.power,
                                              color: Color(0xFFD5DAE3), size: 20)
                                }
                            }
                        }
                    }
                }
        })
    }

    /// Least destructive first, so the pointer travels furthest to reach the
    /// one that throws the most away. Restart and Shut down are dropped
    /// entirely on an account that may not power the machine off, rather than
    /// offered and then refused.
    private var powerActions: [Win32Session.Action] {
        Win32Session.Action.allCases.filter {
            !$0.needsPowerPrivilege || Win32Session.canPowerOff
        }
    }

    private func pagerRow(_ list: [Win32App]) -> Widget {
        Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 14) {
            if pageCount > 1 { pageButton("‹", to: bloc.state.page - 1) }
            Text(!bloc.state.catalogReady ? "Loading apps"
                    : list.isEmpty ? "No apps match \"\(bloc.state.query)\""
                    : pageCount > 1
                        ? "\(list.count) apps  ·  page \(bloc.state.page + 1) of \(pageCount)"
                        : "\(list.count) apps",
                 style: TextStyle(color: Color(0xFF6E7683), fontSize: 12))
            if pageCount > 1 { pageButton("›", to: bloc.state.page + 1) }
        }
    }

    /// The actions, in place of the pager. Least destructive first, so the
    /// pointer travels furthest to reach the one that throws the most away.
    private func powerActionRow() -> Widget {
        Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 8) {
            for action in powerActions { powerRow(action, 34) }
        }
    }


    private func powerRow(_ action: Win32Session.Action, _ height: Double) -> Widget {
        GestureDetector(
            onTap: { self.choosePower(action) },
            child: SizedBox(height: height) {
                ClipRRect(borderRadius: BorderRadius.circular(8)) {
                    ColoredBox(color: action == .shutDown ? Color(0x33FF6B6B)
                                                          : Color(0x1AFFFFFF)) {
                        Padding(padding: EdgeInsets(horizontal: 12, vertical: 0)) {
                            Row(mainAxisSize: .min, crossAxisAlignment: .center,
                                spacing: 8) {
                                MacosIcon(icon: powerGlyph(action),
                                          color: Color(0xFFD5DAE3), size: 15)
                                Text(action.label,
                                     style: TextStyle(color: Color(0xFFE8ECF3),
                                                      fontSize: 13))
                            }
                        }
                    }
                }
            })
    }

    private func powerGlyph(_ action: Win32Session.Action) -> IconData {
        switch action {
        case .lock: return CupertinoIcons.lock_fill
        case .signOut: return CupertinoIcons.square_arrow_right
        case .sleep: return CupertinoIcons.moon_fill
        case .restart: return CupertinoIcons.arrow_clockwise
        case .shutDown: return CupertinoIcons.power
        }
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
        // Every `bloc.state` read below is registered here, so the catalog
        // landing and each icon texture arriving rebuild the grid without the
        // widget having to know which of them happened.
        return withObservationTracking {
            _buildContent()
        } onChange: { [weak self] in
            guard let self, self.mounted else { return }
            self.setState {}
        }
    }

    private func _buildContent() -> Widget {
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
                    let wanted = max(0, min(self.pageCount - 1,
                                            self.bloc.state.page + step))
                    guard wanted != self.bloc.state.page else { return }
                    self.bloc.add(.goToPage(wanted))
                },
                child: ColoredBox(color: Color(0xFF14161A)) {
                Column(mainAxisAlignment: .center, crossAxisAlignment: .center) {
                    SizedBox(width: kLauncherWidth - 140, height: 34) {
                        MacosTextField(
                            controller: search,
                            placeholder: "Search",
                            onChanged: { text in
                                // Back to page one on every keystroke: the
                                // results changed underneath, so the page
                                // number is about a list that no longer
                                // exists.
                                self.bloc.add(.search(text))
                            },
                            onSubmitted: { _ in
                                if let first = self.matches.first { self.launch(first) }
                            },
                            // The launcher opens ready to be typed into, the
                            // way Windows' own Start menu does. Without this
                            // the field only takes keys once it has been
                            // clicked, and typing straight after opening —
                            // which is how anyone uses a launcher — did
                            // nothing at all.
                            autofocus: true)
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
                    if !bloc.state.catalogReady {
                        loading()
                    } else {
                        grid(list)
                    }
                    SizedBox(height: 24)
                    // Tap targets as well as the wheel: a page you can only
                    // reach by scrolling is a page most people never find,
                    // and taps are the one pointer route this framework
                    // delivers without argument.
                    // The footer, and the power UI, in ONE row.
                    //
                    // The power button started life floating in the panel's
                    // bottom-right corner, over the grid, the way Windows'
                    // Start menu draws it. It DREW there and could not be
                    // pressed: neither a GestureDetector inside a `Positioned`
                    // nor `onPointerDown` on the root Listener fires in this
                    // surface, while the same GestureDetector inside the grid's
                    // Column works — which is what the app tiles use. So the
                    // button lives in the Column, on the working input path,
                    // and pressing it SWAPS this row's contents for the
                    // actions rather than floating a menu above it.
                    SizedBox(width: kLauncherWidth - kLauncherMargin, height: 44) {
                        Row(crossAxisAlignment: .center) {
                            SizedBox(width: 40, height: 44)
                            Expanded {
                                Center {
                                    powerOpen ? powerActionRow() : pagerRow(list)
                                }
                            }
                            powerButton()
                        }
                    }
                }
            }))
    }
}
#endif
