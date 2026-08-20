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
let kLauncherWidth = 640.0
let kLauncherHeight = 740.0
let kLauncherGap = 12.0

/// Windows 11's own: a 32pt icon in a 92 x 88 cell, six across.
let kLauncherIcon = 32.0
let kLauncherCell = 92.0
let kLauncherCellH = 88.0
/// The content column. 640 - 2 x 44, which is where Start's search box sits.
let kStartContent = 552.0
/// One row of the All apps list.
let kStartRowH = 40.0
/// Points kept clear at the left and right of the grid.
let kLauncherMargin = 88.0

/// Start's colours, taken from Windows 11 rather than invented.
///
/// The user asked for the same UI, and "the same" includes following the
/// system's own light/dark setting — a dark Start on a light desktop is the
/// one thing that would give it away at a glance. `Win32Control.isDarkMode`
/// reads the same registry value Windows itself reads.
struct StartTheme {
    let dark: Bool

    var background: Color { dark ? Color(0xFF2B2B2B) : Color(0xFFF3F3F3) }
    /// The account bar is a shade off the panel, as Start's is.
    var footer: Color { dark ? Color(0xFF262626) : Color(0xFFEBEBEB) }
    var text: Color { dark ? Color(0xFFFFFFFF) : Color(0xFF1B1B1B) }
    var secondary: Color { dark ? Color(0xFFC8C8C8) : Color(0xFF5D5D5D) }
    var tertiary: Color { dark ? Color(0xFF9A9A9A) : Color(0xFF6E6E6E) }
    var fieldFill: Color { dark ? Color(0xFF373737) : Color(0xFFFBFBFB) }
    var fieldBorder: Color { dark ? Color(0xFF454545) : Color(0xFFDCDCDC) }
    var hover: Color { dark ? Color(0x14FFFFFF) : Color(0x0A000000) }
    var divider: Color { dark ? Color(0x1AFFFFFF) : Color(0x14000000) }
    var accent: Color { Color(0xFF4CC2FF) }
}

/// The power menu's row height and width, shared by the drawing and the
/// arithmetic hit test.
let kPowerRowH = 38.0
let kPowerMenuW = 190.0

/// Start's pinned grid: six across, three down — Windows 11's own shape, and
/// 6 x 104pt is 624pt inside a 780pt panel.
let kPinnedColumns = 6
let kPinnedRows = 3

/// The single source of truth for the launcher.
/// One group of apps in the launcher.
///
/// The grouping is REAL DATA, not something invented: a Start Menu shortcut
/// lives in a folder — "Accessories", "Git", "Python 3.12" — and that folder
/// is what every Windows installer has been putting its apps into for thirty
/// years. Windows 10's own All Apps list grouped by it too. So the default
/// grouping needs no input from anyone, and the user renames a group only
/// when the installer's own name is wrong.
struct LauncherGroup: Equatable {
    /// The Start Menu folder, and the key everything is stored against. Empty
    /// for shortcuts at the top level.
    let key: String
    /// What the launcher shows: the user's name for it, or the folder's.
    let name: String
    let apps: [Win32App]
    let collapsed: Bool
}

/// A row of the launcher's scrolling list: a group's heading, or one row of
/// its tiles. Flattened like this so the list can be LAZY — a machine with
/// three hundred apps builds only what is on screen.
enum LauncherRow {
    case header(LauncherGroup)
    case apps([Win32App])
}

struct LauncherState {
    /// Everything installed, from the Start Menu.
    var apps: [Win32App] = []
    /// Whether the walk has finished. Until it has the UI says so, rather
    /// than showing an empty grid that reads as "you have no apps".
    var catalogReady = false
    /// The search box's text.
    var query = ""
    /// Custom group names, keyed by the Start Menu folder they replace.
    var names: [String: String] = [:]
    /// Folders the user has collapsed.
    var collapsed: Set<String> = []
    /// The group whose name is being edited, if any.
    var renaming: String?

    // Start's own shape: a small pinned grid over a short list of recent
    // things, with everything else one tap away behind "All apps".
    /// Whether the All apps list is showing instead of the pinned view.
    var showingAll = false
    /// Pinned apps, by catalog key, in the order the user put them.
    var pinned: [String] = []
    /// What the user opened lately — the shell's own Recent folder.
    var recent: [Win32FileEntry] = []
    /// Apps whose Start Menu shortcut is new. Windows' Recommended list is
    /// "recently added" as much as "recently opened", and on a machine whose
    /// Recent folder holds only shell-namespace shortcuts — which is this one
    /// — it is the half that has anything in it.
    var recentApps: [Win32App] = []
    var userName = ""
    /// Windows' own light/dark setting, so Start matches everything else on
    /// the machine.
    var dark = true
    /// True while the pinned grid is editable: tapping a tile then removes it
    /// rather than launching it.
    var editingPins = false
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
        /// Fold a group away, or open it again.
        case toggleGroup(String)
        case showAllApps(Bool)
        case toggleEditPins
        case pin(Win32App)
        case unpin(String)
        case recentLoaded([Win32FileEntry], name: String, dark: Bool)
        case recentAppsLoaded([Win32App])
        /// Start renaming a group, or stop.
        case beginRename(String?)
        /// Give a group a name of the user's own. An empty name puts the
        /// installer's folder name back rather than leaving a blank heading.
        case renameGroup(key: String, name: String)
        case launch(Win32App)
        /// The launcher was just shown: open on a clean query.
        case opened
        case closed

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

        case .showAllApps(let showing):
            state.showingAll = showing

        case .toggleEditPins:
            state.editingPins.toggle()

        case .pin(let app):
            let key = IconCache.key(for: app)
            guard !state.pinned.contains(key) else { return }
            state.pinned.append(key)
            _savePins()

        case .unpin(let key):
            state.pinned.removeAll { $0 == key }
            _savePins()

        case .recentLoaded(let entries, let name, let dark):
            state.recent = entries
            state.userName = name
            state.dark = dark
            // One icon per EXTENSION, exactly as the file explorer does it:
            // six recent files are usually three types.
            for entry in entries {
                icons.ensure(key: LauncherBloc.recentKey(entry),
                             path: entry.path, size: 32)
            }

        case .recentAppsLoaded(let apps):
            state.recentApps = apps

        case .toggleGroup(let key):
            if state.collapsed.contains(key) {
                state.collapsed.remove(key)
            } else {
                state.collapsed.insert(key)
            }
            _saveGroups()

        case .beginRename(let key):
            state.renaming = key

        case .renameGroup(let key, let name):
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                state.names.removeValue(forKey: key)
            } else {
                state.names[key] = trimmed
            }
            state.renaming = nil
            _saveGroups()
        case .opened:
            // Nothing to do here any more, and that is the point — see
            // `.closed`. Kept because "the surface was opened" is a real event
            // and the next thing that wants to happen on it belongs here.
            break

        case .closed:
            // THE RESET HAPPENS ON THE WAY DOWN.
            //
            // Always open on an empty query, in the pinned view, not in
            // pinning mode: a launcher that remembers the last search shows
            // you the wrong four apps every time you open it. Doing that when
            // it is SHOWN, though, puts a build and a rasterize between the
            // keypress and the pixels — traced at 14ms to the build alone,
            // and a whole extra frame on screen. Doing it when it is hidden
            // costs the user nothing, because nobody is looking.
            state.query = ""
            state.page = 0
            state.showingAll = false
            state.editingPins = false
            state.renaming = nil
        case .launch(let app):
            // Off the UI thread: the fast path is 8ms but the `.lnk` fallback
            // measured 484ms, and this thread has frames to draw.
            Task.detached { Win32AppCatalog.launch(app) }
        case .catalogLoaded(let apps):
            state.apps = apps
            state.catalogReady = true
            // AFTER the catalog: the seed matches by name, so it has nothing
            // to match against any earlier.
            _loadPins()
            // Same again for "recently added": it is a stat() per shortcut,
            // so it waits for the catalog and runs off this thread.
            Task.detached { [weak self] in
                let added = LauncherBloc.recentlyAdded(apps)
                await MainActor.run { self?.add(.recentAppsLoaded(added)) }
            }
            print("[WinShellLauncher] \(apps.count) apps")
            _warmIcons(apps)
        case .iconsChanged:
            state.iconRevision &+= 1
        }
    }

    /// The apps as groups: the user's names where they gave one, the Start
    /// Menu's folder otherwise, and everything loose at the top level in a
    /// group of its own at the end.
    ///
    /// Alphabetical, because a launcher is scanned rather than read and a
    /// list that reorders itself by app count moves things under the pointer
    /// every time something is installed.
    var groups: [LauncherGroup] {
        var byKey: [String: [Win32App]] = [:]
        for app in state.apps { byKey[app.category, default: []].append(app) }

        return byKey.map { key, apps in
            LauncherGroup(key: key,
                          name: state.names[key] ?? (key.isEmpty ? "Other" : key),
                          apps: apps.sorted {
                              $0.name.localizedCaseInsensitiveCompare($1.name)
                                  == .orderedAscending
                          },
                          collapsed: state.collapsed.contains(key))
        }.sorted {
            // Loose apps last: they are the leftovers, not a category.
            if $0.key.isEmpty != $1.key.isEmpty { return !$0.key.isEmpty }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @ObservationIgnored private var groupsPath: String {
        let base = ProcessInfo.processInfo.environment["APPDATA"]
            ?? NSTemporaryDirectory()
        return base + "\\Starling\\launcher-groups.txt"
    }

    /// `folder<TAB>name<TAB>collapsed`, one per line. Only groups the user has
    /// touched are written — the rest come from the Start Menu every time, so
    /// a newly installed app lands in its own folder's group with no help.
    private func _loadGroups() {
        guard let text = try? String(contentsOfFile: groupsPath, encoding: .utf8)
        else { return }
        for line in text.split(whereSeparator: { $0 == "\r\n" || $0 == "\n" }) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let key = String(parts[0])
            if !parts[1].isEmpty { state.names[key] = String(parts[1]) }
            if parts[2] == "1" { state.collapsed.insert(key) }
        }
    }

    private func _saveGroups() {
        var keys = Set(state.names.keys)
        keys.formUnion(state.collapsed)
        let lines = keys.sorted().map { key in
            "\(key)\t\(state.names[key] ?? "")\t\(state.collapsed.contains(key) ? "1" : "0")"
        }
        let path = groupsPath
        let text = lines.joined(separator: "\r\n")
        Task.detached {
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir,
                                                     withIntermediateDirectories: true)
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// The apps installed in the last month, newest first.
    ///
    /// A Start Menu shortcut is written when the app is installed, so its
    /// modification time IS the install date — no package database, no
    /// registry walk, and it works for the ones that never registered
    /// themselves properly either.
    static func recentlyAdded(_ apps: [Win32App], limit: Int = 6) -> [Win32App] {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        var dated: [(app: Win32App, when: Date)] = []
        for app in apps {
            guard let attributes = try? fm.attributesOfItem(atPath: app.shortcutPath),
                  let when = attributes[.modificationDate] as? Date,
                  when > cutoff else { continue }
            dated.append((app, when))
        }
        return dated.sorted { $0.when > $1.when }.prefix(limit).map { $0.app }
    }

    /// Directories share one icon; files share one per extension — the same
    /// bargain the file explorer strikes, for the same reason.
    static func recentKey(_ entry: Win32FileEntry) -> String {
        entry.isDirectory ? "\u{1}dir" : "\u{1}ext:\(entry.ext)"
    }

    @ObservationIgnored private var pinsPath: String {
        let base = ProcessInfo.processInfo.environment["APPDATA"]
            ?? NSTemporaryDirectory()
        return base + "\\Starling\\launcher-pins.txt"
    }

    /// Seeded on first run from what a Windows machine actually has, matched
    /// by name against the catalog — a pinned grid that comes up empty is a
    /// worse first impression than one holding the obvious six.
    private static let kSeedPins = ["edge", "file explorer", "terminal",
                                    "notepad", "settings", "calculator"]

    private func _loadPins() {
        if let text = try? String(contentsOfFile: pinsPath, encoding: .utf8) {
            state.pinned = text.split(whereSeparator: { $0 == "\r\n" || $0 == "\n" })
                .map(String.init).filter { !$0.isEmpty }
            return
        }
        var seeded: [String] = []
        for wanted in Self.kSeedPins {
            guard let app = state.apps.first(where: {
                $0.name.lowercased().contains(wanted)
            }) else { continue }
            let key = IconCache.key(for: app)
            if !seeded.contains(key) { seeded.append(key) }
        }
        // Fill the row out from the catalog when the names above are not on
        // this machine — Notepad and Calculator are Store apps and have no
        // Start Menu shortcut on a fresh install, which left the grid holding
        // two icons and a lot of nothing. Loose shortcuts first: an app filed
        // at the top level of the Start Menu is one somebody installed on
        // purpose, while the folders are full of Administrative Tools.
        for app in state.apps where seeded.count < kPinnedColumns {
            guard app.category.isEmpty else { continue }
            let key = IconCache.key(for: app)
            if !seeded.contains(key) { seeded.append(key) }
        }
        state.pinned = seeded
    }

    private func _savePins() {
        let path = pinsPath
        let text = state.pinned.joined(separator: "\r\n")
        Task.detached {
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir,
                                                     withIntermediateDirectories: true)
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// The pinned apps, resolved against the catalog and in the user's order.
    var pinnedApps: [Win32App] {
        state.pinned.compactMap { key in
            state.apps.first { IconCache.key(for: $0) == key }
        }
    }

    private func _start() {
        _loadGroups()

        // Recent items and the user's name: a folder read and a lookup, both
        // off the UI thread like everything else here.
        Task.detached { [weak self] in
            let recent = Win32Files.recent(limit: 6)
            let name = Win32Files.userName()
            let dark = Win32Control.isDarkMode
            await MainActor.run {
                self?.add(.recentLoaded(recent, name: name, dark: dark))
            }
        }
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
    /// The grouped list's scroll position.
    private let scroll = ScrollController()
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
        flwin32_trace("launcher: didToggle begin")
        if Win32WindowedHost.host?.isVisible == true {
            bloc.add(.opened)
            flwin32_trace("launcher: didToggle end (shown)")
            return
        }
        // Hidden: put it back the way it should come up, and push that through
        // the engine now, so the next open is a window becoming visible and
        // nothing else.
        //
        // The redraw is deferred by a frame because the reset only marks the
        // tree dirty — the build happens on the engine's next frame, and
        // asking to rasterize before that would push the OLD tree through.
        search.text = ""
        bloc.add(.closed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Win32WindowedHost.host?.requestRedraw()
            flwin32_trace("launcher: hidden redraw pushed")
        }
        flwin32_trace("launcher: didToggle end (hidden)")
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

    private var theme: StartTheme { StartTheme(dark: bloc.state.dark) }

    // MARK: - Build
    //
    // Windows 11's Start, to its own geometry: a 640pt panel, a 552pt content
    // column, a 6-wide grid of 32pt icons over a short Recommended list, and
    // an account bar along the bottom. The numbers are Microsoft's, not ours,
    // because the ask was the same UI — and following the system's own
    // light/dark setting is part of that.
    //
    // What is NOT the same is what it costs. Theirs takes 120-135ms to appear
    // on this machine, measured, every time it is opened. This process is
    // already running and hidden, and everything below was computed on a
    // background task long before the user pressed anything, so opening it is
    // a window becoming visible: 10-81ms.

    /// One pinned tile: 32pt icon, name under it, in a 92 x 88 cell.
    private func tile(_ app: Win32App) -> Widget {
        let key = IconCache.key(for: app)
        let editing = bloc.state.editingPins
        let isPinned = bloc.state.pinned.contains(key)
        return GestureDetector(
            onTap: {
                guard editing else { return self.launch(app) }
                self.bloc.add(isPinned ? .unpin(key) : .pin(app))
            },
            child: SizedBox(width: kLauncherCell, height: kLauncherCellH) {
                Column(mainAxisAlignment: .center, crossAxisAlignment: .center) {
                    // While pinning, every tile says what a tap would do to
                    // it. Without this the mode is invisible and the only way
                    // to find out is to press something.
                    if editing {
                        SizedBox(height: 13) {
                            MacosIcon(icon: isPinned ? CupertinoIcons.minus_circle_fill
                                                     : CupertinoIcons.plus_circle,
                                      color: isPinned ? Color(0xFFE06C6C)
                                                      : theme.tertiary,
                                      size: 12)
                        }
                    }
                    appIcon(key, kLauncherIcon)
                    SizedBox(height: 6)
                    SizedBox(width: kLauncherCell - 8, height: 30) {
                        Text(app.name,
                             style: TextStyle(color: theme.text, fontSize: 12,
                                              height: 1.25),
                             textAlign: .center,
                             overflow: .ellipsis,
                             maxLines: 2)
                    }
                }
            })
    }

    /// An app icon, or the placeholder that stands in until it rasterizes.
    private func appIcon(_ key: String, _ side: Double) -> Widget {
        if let icon = bloc.icons.view(key, side: side) { return icon }
        return SizedBox(width: side, height: side) {
            Center {
                MacosIcon(icon: CupertinoIcons.app_badge,
                          color: theme.tertiary, size: side * 0.7)
            }
        }
    }

    /// One row of the All apps list — Windows' list is single-column rows of
    /// a 24pt icon and a name, not a grid.
    private func appRow(_ app: Win32App, indented: Bool) -> Widget {
        let key = IconCache.key(for: app)
        let editing = bloc.state.editingPins
        let isPinned = bloc.state.pinned.contains(key)
        return GestureDetector(
            onTap: {
                guard editing else { return self.launch(app) }
                self.bloc.add(isPinned ? .unpin(key) : .pin(app))
            },
            child: SizedBox(width: kStartContent, height: kStartRowH) {
                Padding(padding: EdgeInsets(left: indented ? 30 : 10, top: 2,
                                            right: 10, bottom: 2)) {
                    ClipRRect(borderRadius: BorderRadius.circular(4)) {
                        ColoredBox(color: Color(0x00000000)) {
                            Row(crossAxisAlignment: .center, spacing: 12) {
                                appIcon(key, 24)
                                Expanded {
                                    Text(app.name,
                                         style: TextStyle(color: theme.text,
                                                          fontSize: 13),
                                         overflow: .ellipsis, maxLines: 1)
                                }
                                if editing {
                                    MacosIcon(icon: isPinned
                                                  ? CupertinoIcons.minus_circle_fill
                                                  : CupertinoIcons.plus_circle,
                                              color: isPinned ? Color(0xFFE06C6C)
                                                              : theme.tertiary,
                                              size: 14)
                                }
                            }
                        }
                    }
                }
            })
    }

    // MARK: - Power

    private func choosePower(_ action: Win32Session.Action) {
        setState { powerOpen = false }
        // Out of the way first: whatever happens next, the launcher should not
        // be the last thing on screen during it.
        Win32WindowedHost.host?.setVisible(false)
        Task.detached { Win32Session.perform(action) }
    }

    /// The power button, bottom-right of the account bar, where Windows puts
    /// it.
    ///
    /// It opens a MENU rather than doing anything. That is not politeness, it
    /// is the confirmation: a single click that ends the session — with
    /// whatever is unsaved in whatever is open — is not something to put one
    /// pointer-slip away from the app grid.
    private func powerButton() -> Widget {
        GestureDetector(
            onTap: { self.setState { self.powerOpen.toggle() } },
            child: SizedBox(width: 36, height: 36) {
                Center {
                    ClipRRect(borderRadius: BorderRadius.circular(4)) {
                        ColoredBox(color: powerOpen ? theme.hover
                                                    : Color(0x00000000)) {
                            SizedBox(width: 36, height: 36) {
                                Center {
                                    MacosIcon(icon: CupertinoIcons.power,
                                              color: theme.text, size: 18)
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

    private func powerActionRow() -> Widget {
        Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 6) {
            for action in powerActions { powerRow(action) }
        }
    }

    private func powerRow(_ action: Win32Session.Action) -> Widget {
        GestureDetector(
            onTap: { self.choosePower(action) },
            child: SizedBox(height: 32) {
                ClipRRect(borderRadius: BorderRadius.circular(4)) {
                    ColoredBox(color: action == .shutDown ? Color(0x33FF6B6B)
                                                          : theme.hover) {
                        Padding(padding: EdgeInsets(horizontal: 10, vertical: 0)) {
                            Row(mainAxisSize: .min, crossAxisAlignment: .center,
                                spacing: 7) {
                                MacosIcon(icon: powerGlyph(action),
                                          color: theme.text, size: 14)
                                Text(action.label,
                                     style: TextStyle(color: theme.text,
                                                      fontSize: 12))
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

    // MARK: - The All apps list

    /// Groups flattened into rows, so the list can be lazy.
    ///
    /// Windows 11's All apps is a flat alphabetical list; Windows 10's grouped
    /// by the Start Menu FOLDER, which is real data every installer has been
    /// writing for thirty years. We keep the grouping — it was asked for, and
    /// it is the better answer for the 79 shortcuts on this machine — and draw
    /// it as Windows draws a grouped list: a heading, then indented rows.
    private func groupRows() -> [LauncherRow] {
        var rows: [LauncherRow] = []
        for group in bloc.groups {
            rows.append(.header(group))
            guard !group.collapsed else { continue }
            for app in group.apps { rows.append(.apps([app])) }
        }
        return rows
    }

    private func groupRow(_ rows: [LauncherRow], _ index: Int) -> Widget {
        guard index < rows.count else { return SizedBox(height: 0) }
        switch rows[index] {
        case .header(let group): return groupHeader(group)
        case .apps(let apps):
            guard let app = apps.first else { return SizedBox(height: 0) }
            return appRow(app, indented: true)
        }
    }

    /// A group's heading: its name, how many apps are in it, and the two
    /// things you can do to it.
    ///
    /// Tapping the heading folds the group away. Tapping the pencil renames
    /// it — in place, with a field that takes the keyboard as it appears,
    /// because a launcher that opens a dialog to rename a heading has lost
    /// the plot.
    private func groupHeader(_ group: LauncherGroup) -> Widget {
        SizedBox(width: kStartContent, height: kStartRowH) {
            Padding(padding: EdgeInsets(left: 10, top: 6, right: 10, bottom: 2)) {
                bloc.state.renaming == group.key
                    ? renameField(group)
                    : Row(crossAxisAlignment: .center, spacing: 8) {
                        GestureDetector(
                            onTap: { self.bloc.add(.toggleGroup(group.key)) },
                            child: Row(mainAxisSize: .min, crossAxisAlignment: .center,
                                       spacing: 7) {
                                MacosIcon(icon: group.collapsed
                                              ? CupertinoIcons.chevron_right
                                              : CupertinoIcons.chevron_down,
                                          color: self.theme.secondary, size: 11)
                                Text(group.name,
                                     style: TextStyle(color: self.theme.text,
                                                      fontSize: 13, fontWeight: .w600))
                                Text("\(group.apps.count)",
                                     style: TextStyle(color: self.theme.tertiary,
                                                      fontSize: 12))
                            })
                        // Pushed to the RIGHT EDGE rather than sitting after
                        // the name: a target whose position depends on how
                        // long the group is called is a target you have to
                        // look for every time.
                        Expanded { SizedBox(height: 1) }
                        GestureDetector(
                            onTap: { self.bloc.add(.beginRename(group.key)) },
                            child: Padding(padding: EdgeInsets(horizontal: 10, vertical: 4)) {
                                MacosIcon(icon: CupertinoIcons.pencil,
                                          color: self.theme.tertiary, size: 13)
                            })
                    }
            }
        }
    }

    private func renameField(_ group: LauncherGroup) -> Widget {
        let controller = TextEditingController()
        controller.text = group.name
        return SizedBox(width: 280, height: 26) {
            MacosTextField(
                controller: controller,
                placeholder: group.key.isEmpty ? "Other" : group.key,
                onSubmitted: { text in
                    self.bloc.add(.renameGroup(key: group.key, name: text))
                },
                autofocus: true)
        }
    }

    /// Shown while the Start Menu walk is still running on its own thread.
    private func loading() -> Widget {
        SizedBox(height: 300) {
            Column(mainAxisAlignment: .center, crossAxisAlignment: .center) {
                SizedBox(width: 200) {
                    MacosProgressIndicator()
                }
                SizedBox(height: 16)
                Text("Reading the Start Menu",
                     style: TextStyle(color: theme.tertiary, fontSize: 13))
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

    // MARK: - Start's own layout

    /// Start's search box: a 34pt field with the magnifier inside it,
    /// hairline bordered, 4pt corners.
    ///
    /// The chrome is the FIELD'S OWN decoration rather than a box drawn around
    /// it. Wrapping it in our own left two rectangles on screen: the field
    /// paints its focus ring outside whatever decoration it is given, so the
    /// only way to have exactly one is to make that one Windows-shaped and
    /// turn the ring off.
    private func searchBox() -> Widget {
        SizedBox(width: kStartContent, height: 34) {
            MacosTextField(
                controller: search,
                placeholder: "Search for apps and files",
                prefix: Padding(padding: EdgeInsets(left: 6, top: 0, right: 0, bottom: 0)) {
                    MacosIcon(icon: CupertinoIcons.search,
                              color: theme.secondary, size: 14)
                },
                onChanged: { text in
                    // Back to page one on every keystroke: the results changed
                    // underneath, so the page number is about a list that no
                    // longer exists.
                    self.bloc.add(.search(text))
                },
                onSubmitted: { _ in
                    if let first = self.matches.first { self.launch(first) }
                },
                style: TextStyle(color: self.theme.text, fontSize: 13),
                padding: EdgeInsets(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                    color: theme.fieldFill,
                    border: Border.all(color: theme.fieldBorder, width: 1),
                    borderRadius: BorderRadius.all(Radius(circular: 4))),
                showFocusRing: false,
                // Start opens ready to be typed into. Without this the field
                // only takes keys once it has been clicked, and typing straight
                // after opening — which is how anyone uses a launcher — did
                // nothing at all.
                autofocus: true)
        }
    }

    /// A section heading with an action on the right — "Pinned … All apps ›".
    private func sectionRow(_ title: String, _ trailing: Widget?) -> Widget {
        SizedBox(width: kStartContent, height: 32) {
            Padding(padding: EdgeInsets(horizontal: 10, vertical: 0)) {
                Row(crossAxisAlignment: .center) {
                    Text(title,
                         style: TextStyle(color: theme.text, fontSize: 13,
                                          fontWeight: .w600))
                    Expanded { SizedBox(height: 1) }
                    if let trailing { trailing }
                }
            }
        }
    }

    /// Start's small right-hand buttons: label, then a chevron, on a subtle
    /// fill. In a Row inside the Column, which is the input path that works
    /// here — see the power button's note.
    private func pill(_ label: String, _ glyph: IconData?, _ active: Bool,
                      leading: Bool = false,
                      _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: action,
            child: SizedBox(height: 26) {
                ClipRRect(borderRadius: BorderRadius.circular(4)) {
                    ColoredBox(color: active ? theme.hover : Color(0x00000000)) {
                        Padding(padding: EdgeInsets(horizontal: 10, vertical: 0)) {
                            Row(mainAxisSize: .min, crossAxisAlignment: .center,
                                spacing: 6) {
                                if leading, let glyph {
                                    MacosIcon(icon: glyph, color: theme.text, size: 11)
                                }
                                Text(label,
                                     style: TextStyle(color: theme.text, fontSize: 12))
                                if !leading, let glyph {
                                    MacosIcon(icon: glyph, color: theme.text, size: 11)
                                }
                            }
                        }
                    }
                }
            })
    }

    /// The pinned grid, or the message that says how to fill it.
    private func pinnedGrid() -> Widget {
        let apps = bloc.pinnedApps
        guard !apps.isEmpty else {
            return SizedBox(width: kStartContent,
                            height: Double(kPinnedRows) * kLauncherCellH) {
                Center {
                    Text("Nothing pinned — open All apps, then Pin apps.",
                         style: TextStyle(color: theme.tertiary, fontSize: 12))
                }
            }
        }
        // Four rows when there is nothing to recommend, three when there is:
        // Windows does the same trade — its "More pins" layout grows the grid
        // into the space Recommended would have taken.
        let maxRows = recommendations.isEmpty ? kPinnedRows + 1 : kPinnedRows
        var rows: [Widget] = []
        var index = 0
        while index < apps.count, rows.count < maxRows {
            let end = min(index + kPinnedColumns, apps.count)
            rows.append(Row(mainAxisAlignment: .start, mainAxisSize: .min) {
                for app in apps[index..<end] { tile(app) }
            })
            index = end
        }
        // The FULL height either way, so Recommended sits where it sits
        // whether six apps are pinned or eighteen — Windows' Start does not
        // slide its second heading up when the grid is half empty.
        return SizedBox(width: kStartContent,
                        height: Double(maxRows) * kLauncherCellH) {
            Column(mainAxisSize: .min, crossAxisAlignment: .start, children: rows)
        }
    }

    /// Files opened lately first, then apps installed lately — which is what
    /// Windows' Recommended mixes too.
    private var recommendations: [Widget] {
        var out: [Widget] = bloc.state.recent.map { recentTile($0) }
        for app in bloc.state.recentApps where out.count < 6 {
            out.append(addedTile(app))
        }
        return out
    }

    private func recommended() -> Widget {
        let tiles = recommendations
        guard !tiles.isEmpty else {
            return SizedBox(width: kStartContent, height: 60) {
                Center {
                    Text("Files you open will show up here.",
                         style: TextStyle(color: theme.tertiary, fontSize: 12))
                }
            }
        }
        var rows: [Widget] = []
        var index = 0
        while index < tiles.count {
            let end = min(index + 2, tiles.count)
            rows.append(Row(mainAxisSize: .min, crossAxisAlignment: .center,
                            children: Array(tiles[index..<end])))
            index = end
        }
        return SizedBox(width: kStartContent) {
            Column(mainAxisSize: .min, crossAxisAlignment: .start, children: rows)
        }
    }

    /// A recently installed app, in the same two-column row as a recent file.
    private func addedTile(_ app: Win32App) -> Widget {
        let key = IconCache.key(for: app)
        return GestureDetector(
            onTap: { self.launch(app) },
            child: SizedBox(width: kStartContent / 2, height: 48) {
                Padding(padding: EdgeInsets(left: 10, top: 3, right: 6, bottom: 3)) {
                    Row(crossAxisAlignment: .center, spacing: 10) {
                        appIcon(key, 24)
                        Expanded {
                            Column(mainAxisAlignment: .center,
                                   crossAxisAlignment: .start) {
                                Text(app.name,
                                     style: TextStyle(color: theme.text, fontSize: 12),
                                     overflow: .ellipsis, maxLines: 1)
                                Text("Recently added",
                                     style: TextStyle(color: theme.tertiary,
                                                      fontSize: 11),
                                     overflow: .ellipsis, maxLines: 1)
                            }
                        }
                    }
                }
            })
    }

    private func recentTile(_ entry: Win32FileEntry) -> Widget {
        GestureDetector(
            onTap: {
                Win32WindowedHost.host?.setVisible(false)
                let path = entry.path
                Task.detached { Win32AppCatalog.open(path) }
            },
            child: SizedBox(width: kStartContent / 2, height: 48) {
                Padding(padding: EdgeInsets(left: 10, top: 3, right: 6, bottom: 3)) {
                    Row(crossAxisAlignment: .center, spacing: 10) {
                        if let icon = bloc.icons.view(recentKey(entry), side: 24) {
                            icon
                        } else {
                            MacosIcon(icon: entry.isDirectory
                                          ? CupertinoIcons.folder_fill
                                          : CupertinoIcons.doc_fill,
                                      color: theme.tertiary, size: 20)
                        }
                        Expanded {
                            Column(mainAxisAlignment: .center,
                                   crossAxisAlignment: .start) {
                                Text(entry.name,
                                     style: TextStyle(color: theme.text, fontSize: 12),
                                     overflow: .ellipsis, maxLines: 1)
                                Text(entry.isDirectory ? "Folder"
                                        : entry.ext.isEmpty ? "File"
                                        : entry.ext.uppercased() + " file",
                                     style: TextStyle(color: theme.tertiary,
                                                      fontSize: 11),
                                     overflow: .ellipsis, maxLines: 1)
                            }
                        }
                    }
                }
            })
    }

    /// The bar along the bottom: who is signed in, and the power button. Its
    /// own shade, full width, exactly as Start's is.
    private func accountBar() -> Widget {
        SizedBox(width: kLauncherWidth, height: 60) {
            ColoredBox(color: theme.footer) {
                Padding(padding: EdgeInsets(horizontal: 44, vertical: 0)) {
                    Row(crossAxisAlignment: .center) {
                        if powerOpen {
                            Expanded { Center { powerActionRow() } }
                        } else {
                            Row(mainAxisSize: .min, crossAxisAlignment: .center,
                                spacing: 12) {
                                // The initial, in a disc. A real account
                                // picture needs the user tile from the shell's
                                // own store and it is absent on plenty of
                                // local accounts; a letter is honest and
                                // always there.
                                SizedBox(width: 32, height: 32) {
                                    ClipRRect(borderRadius: BorderRadius.circular(16)) {
                                        ColoredBox(color: theme.dark
                                                       ? Color(0xFF4A4A4A)
                                                       : Color(0xFFD0D0D0)) {
                                            Center {
                                                Text(initial,
                                                     style: TextStyle(
                                                        color: theme.text,
                                                        fontSize: 14,
                                                        fontWeight: .w600))
                                            }
                                        }
                                    }
                                }
                                Text(bloc.state.userName.isEmpty ? "Signed in"
                                                                 : bloc.state.userName,
                                     style: TextStyle(color: theme.text, fontSize: 13))
                            }
                            Expanded { SizedBox(height: 1) }
                        }
                        powerButton()
                    }
                }
            }
        }
    }

    private func recentKey(_ entry: Win32FileEntry) -> String {
        LauncherBloc.recentKey(entry)
    }

    private var initial: String {
        let name = bloc.state.userName
        guard let first = name.first else { return "?" }
        return String(first).uppercased()
    }

    /// "Pinned … All apps ›"
    private func pinnedHeader() -> Widget {
        sectionRow("Pinned",
                   Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 6) {
                       if bloc.state.editingPins {
                           pill("Done", CupertinoIcons.checkmark, true) {
                               self.bloc.add(.toggleEditPins)
                           }
                       }
                       pill("All apps", CupertinoIcons.chevron_right, false) {
                           self.bloc.add(.showAllApps(true))
                       }
                   })
    }

    /// "‹ Back … All apps … Pin apps"
    ///
    /// Pinning lives HERE rather than on the pinned grid, because this is the
    /// only view that shows an app you have not pinned yet. Turning it on
    /// makes a row's tap add or remove the pin instead of launching it, in
    /// both views — one mode, so leaving this list with it still on does not
    /// silently change what the pinned grid does.
    private func allAppsHeader() -> Widget {
        sectionRow("All apps",
                   Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 6) {
                       pill(bloc.state.editingPins ? "Done" : "Pin apps",
                            bloc.state.editingPins ? CupertinoIcons.checkmark
                                                   : CupertinoIcons.pin_fill,
                            bloc.state.editingPins, leading: true) {
                           self.bloc.add(.toggleEditPins)
                       }
                       pill("Back", CupertinoIcons.chevron_left, false, leading: true) {
                           self.bloc.add(.showAllApps(false))
                       }
                   })
    }

    /// Search results: a list, the way Start answers a query — not the pinned
    /// grid rearranged.
    private func searchResults() -> Widget {
        let list = matches
        guard !list.isEmpty else {
            return Center {
                Text("No results for \"\(bloc.state.query)\"",
                     style: TextStyle(color: theme.tertiary, fontSize: 13))
            }
        }
        return ListView(
            controller: scroll,
            itemCount: list.count,
            itemBuilder: { [weak self] _, index in
                guard let self, index < list.count else { return SizedBox(height: 0) }
                return self.appRow(list[index], indented: false)
            })
    }

    private func _buildContent() -> Widget {
        let searching = !bloc.state.query.isEmpty
        return Directionality(
            textDirection: .ltr,
            child: ColoredBox(color: theme.background) {
                Column(mainAxisAlignment: .start, crossAxisAlignment: .center) {
                    SizedBox(height: 26)
                    searchBox()
                    SizedBox(height: 22)

                    // Nothing to show YET is different from nothing to show.
                    //
                    // The catalog is read off the UI thread, so there is a
                    // window — small, but real on a cold machine — where the
                    // launcher is up and the Start Menu walk has not finished.
                    // An empty grid reads as "you have no apps"; this reads as
                    // what it is.
                    if !bloc.state.catalogReady {
                        loading()
                        Expanded { SizedBox(width: 1) }
                    } else if searching {
                        sectionRow("Best match", nil)
                        Expanded { SizedBox(width: kStartContent) { searchResults() } }
                    } else if bloc.state.showingAll {
                        allAppsHeader()
                        Expanded {
                            SizedBox(width: kStartContent) {
                                ListView(
                                    controller: scroll,
                                    itemCount: allRows.count,
                                    itemBuilder: { [weak self] _, index in
                                        guard let self else { return SizedBox(height: 0) }
                                        return self.groupRow(self.allRows, index)
                                    })
                            }
                        }
                    } else {
                        pinnedHeader()
                        pinnedGrid()
                        SizedBox(height: 18)
                        sectionRow("Recommended", nil)
                        recommended()
                        Expanded { SizedBox(width: 1) }
                    }

                    accountBar()
                }
            })
    }

    /// Built once per build, not once per row: `groupRows()` walks every group
    /// and the ListView's builder is called for each visible row.
    private var allRows: [LauncherRow] { groupRows() }
}
#endif
