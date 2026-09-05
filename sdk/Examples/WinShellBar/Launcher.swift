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
/// SIZED FROM THE REAL ONE. Windows 11's Start on this machine measures
/// 1664 x 1728 physical at 200%, so 832 x 864pt — taken off the running menu
/// with an edge scan, not from a design doc. Ours was 640 x 740, which is
/// what Start was two Windows versions ago; matching it is what makes the two
/// read as the same object rather than as an imitation of one.
let kLauncherWidth = 832.0
let kLauncherHeight = 864.0
let kLauncherGap = 12.0

/// Windows 11's own: a 32pt icon in a 92 x 88 cell, EIGHT across.
let kLauncherIcon = 32.0
let kLauncherCell = 92.0
let kLauncherCellH = 88.0
/// The content column. 832 - 2 x 44, which is where Start's search box sits.
let kStartContent = 744.0
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

/// Start's pinned grid: EIGHT across, two down. Counted off the real one —
/// fifteen apps in two rows of eight — where ours showed six in a single row
/// and left the rest of the width empty.
let kPinnedColumns = 8
let kPinnedRows = 2

/// The All section's category cards: four across the content column
/// (4 x 174 + 3 x 16 = 744), each a 2 x 2 preview of the apps inside with the
/// category's name beneath, which is the shape Windows 11 switched to.
let kCategoryCard = 174.0
let kCategoryCardH = 150.0
let kCategoryGap = 16.0
let kCategoryColumns = 4

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

/// The two ways Start lists everything installed: cards for each category, or
/// one long alphabetical-by-group list. Windows offers both behind the
/// "View:" control at the right of the All heading and opens on cards.
enum AllView {
    case category
    case list
}

/// The categories the card view groups by.
///
/// Windows derives its own from app metadata we are not given — there is no
/// API for "what kind of app is this" — so this is a keyword match over the
/// app's name, with the Start Menu folder as a fallback. It is an
/// APPROXIMATION on purpose, and the folder grouping stays the truth: the
/// "View: List" switch shows it, unclassified and exactly as installers wrote
/// it. A card view of forty one-app folders is not what Start looks like, and
/// that is the whole reason this exists.
enum StartCategory: String, CaseIterable {
    case developer = "Developer Tools"
    case productivity = "Productivity"
    case utilities = "Utilities & Tools"
    case creativity = "Creativity"
    case communication = "Communication"
    case games = "Games"
    case other = "Other"

    private static let keywords: [(StartCategory, [String])] = [
        (.developer, ["visual studio", "sdk", "git", "python", "terminal",
                      "powershell", "command prompt", "wsl", "ubuntu", "debug",
                      "cmd", "kit", "developer", "package manager", "alacritty",
                      "idle", "docs", "manuals"]),
        (.communication, ["teams", "outlook", "mail", "phone link", "whatsapp",
                          "linkedin", "quick assist", "skype", "chat"]),
        (.creativity, ["paint", "photo", "camera", "clipchamp", "media player",
                       "snipping", "sound recorder", "imagemagick", "gimp",
                       "creative", "design"]),
        (.games, ["xbox", "solitaire", "game", "minecraft"]),
        (.productivity, ["notepad", "sticky notes", "to do", "onedrive",
                         "office", "word", "excel", "powerpoint", "copilot",
                         "calculator", "clock", "calendar", "edge", "chrome",
                         "firefox", "store", "news", "weather"]),
        (.utilities, ["settings", "control panel", "task", "manager", "disk",
                      "defragment", "diagnostic", "monitor", "security",
                      "defender", "backup", "recovery", "registry", "system",
                      "administrative", "services", "event viewer", "policy",
                      "magnifier", "narrator", "voice", "captions", "keyboard",
                      "accessibility", "remote desktop", "amd", "nvidia",
                      "driver", "install"]),
    ]

    static func of(_ app: Win32App) -> StartCategory {
        let hay = (app.name + " " + app.category).lowercased()
        for (category, words) in keywords where words.contains(where: hay.contains) {
            return category
        }
        return .other
    }
}

/// One row of the single scroll Start now is: the pinned grid, the
/// pinned grid and the whole app list live in the same list rather than on
/// two pages, so they scroll together.
enum StartRow {
    case pinnedHeader
    case pinnedGrid
    case allHeader
    case categoryCards([LauncherGroup])
    case groupHeader(LauncherGroup)
    case app(Win32App)
    case gap(Double)
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

    // Start's own shape: a pinned grid over a short list of recent things,
    // and then EVERY app in the same scroll — Windows 11 stopped putting the
    // app list behind an "All apps" page, so neither do we.
    /// How the All section lists apps. Windows' own switcher, same default.
    var allView: AllView = .category
    /// The category card the user opened, if any: its apps replace the grid
    /// of cards in place, which is what tapping a card does in Start.
    var expandedGroup: String?
    /// Pinned apps, by catalog key, in the order the user put them.
    var pinned: [String] = []
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
        /// Cards or one long list, and which card is open.
        case setAllView(AllView)
        case expandGroup(String?)
        case toggleEditPins
        case pin(Win32App)
        case unpin(String)
        /// Who is logged in, and whether the system is in dark mode. Was
        /// `recentLoaded` and carried the Recent folder too, until
        /// Recommended was removed.
        case shellInfoLoaded(name: String, dark: Bool)
        /// The system's light/dark setting moved while we were running.
        case themeChanged(dark: Bool)
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

        case .setAllView(let view):
            state.allView = view
            state.expandedGroup = nil
        case .expandGroup(let key):
            state.expandedGroup = key

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

        case .themeChanged(let dark):
            state.dark = dark

        case .shellInfoLoaded(let name, let dark):
            state.userName = name
            state.dark = dark

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
            state.expandedGroup = nil
            state.editingPins = false
            state.renaming = nil
        case .launch(let app):
            // OUR file explorer, not Windows'. The Start Menu catalog's "File
            // Explorer" entry launches explorer.exe; this shell has its own,
            // reached from the dock's Files tile and Win+E, and the launcher
            // is the one place it was still missing (the user's report:
            // "in the start menu, there is no mention of our file explorer").
            // Redirect the tile rather than inventing a second one, so the
            // familiar name and yellow folder stay and only the destination
            // changes. On the UI thread, like the dock: opening it is a
            // ShowWindow on the hosted surface (--oneview) or a spawn of the
            // --files window (separate launcher process), both fast.
            if Self.isWindowsFileExplorer(app) {
                FilesWindow.openFileExplorer()
                return
            }
            // Off the UI thread: the fast path is 8ms but the `.lnk` fallback
            // measured 484ms, and this thread has frames to draw.
            Task.detached { Win32AppCatalog.launch(app) }
        case .catalogLoaded(let apps):
            state.apps = apps
            state.catalogReady = true
            // AFTER the catalog: the seed matches by name, so it has nothing
            // to match against any earlier.
            _loadPins()
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

    /// The groups the CARD view shows: categories, largest first, and every
    /// category that has nothing in it left out. `groups` — the Start Menu
    /// folders — remains what the list view shows.
    var cardGroups: [LauncherGroup] {
        var byCategory: [StartCategory: [Win32App]] = [:]
        for app in state.apps { byCategory[StartCategory.of(app), default: []].append(app) }
        return StartCategory.allCases.compactMap { category in
            guard let apps = byCategory[category], !apps.isEmpty else { return nil }
            return LauncherGroup(
                key: "\u{1}cat\u{1}" + category.rawValue,
                name: category.rawValue,
                apps: apps.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                },
                collapsed: false)
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

    /// Windows' own File Explorer, however the catalog recorded it: the
    /// AppsFolder id `Microsoft.Windows.Explorer`, or the Start Menu shortcut
    /// whose display name is "File Explorer" (empty target, no id). Matched so
    /// its launcher tile opens THIS shell's file explorer instead of
    /// explorer.exe — the same redirection the dock's Files tile is. Name is a
    /// fair signal here: `kSeedPins` already keys on "file explorer", and
    /// nothing else on a Windows install carries that name.
    static func isWindowsFileExplorer(_ app: Win32App) -> Bool {
        if app.appUserModelID.caseInsensitiveCompare("Microsoft.Windows.Explorer")
            == .orderedSame {
            return true
        }
        return app.name.caseInsensitiveCompare("File Explorer") == .orderedSame
    }

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
        // Fill BOTH rows, not one: the grid reserves two rows of eight, and a
        // seed that stops at six leaves a band of empty panel where Windows
        // has fifteen apps.
        for app in state.apps where seeded.count < kPinnedColumns * kPinnedRows {
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

        // The user's name and the system theme: two lookups, off the UI
        // thread like everything else here.
        Task.detached { [weak self] in
            let name = Win32Files.userName()
            let dark = Win32Control.isDarkMode
            await MainActor.run { self?.add(.shellInfoLoaded(name: name, dark: dark)) }
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
    /// Non-nil when the launcher runs as a SURFACE VIEW inside the one-app
    /// shell (`--oneshell`) rather than as its own process: the engine view
    /// id, used to register for the surface's toggle notifications instead
    /// of the process host's.
    let surfaceId: Int?
    /// True when the launcher is a LAYER of the dock's own tree (`--oneview`):
    /// no window-side registrations at all — the dock owns visibility, sends
    /// the bloc's opened/closed itself, and this widget mounts fresh per
    /// open (so the search controller starts empty for free).
    let embedded: Bool
    /// How an embedded launcher gets itself out of the way (launching an app
    /// hides Start first, everywhere). Its own window it can hide; a layer
    /// of the dock's tree has to ask the dock — hiding "the host" there is
    /// hiding the WHOLE full-screen chrome window, dock and all, which is
    /// exactly what the first --oneview tile click did.
    let onRequestClose: (() -> Void)?
    init(surfaceId: Int? = nil, embedded: Bool = false,
         onRequestClose: (() -> Void)? = nil) {
        self.surfaceId = surfaceId
        self.embedded = embedded
        self.onRequestClose = onRequestClose
        super.init()
    }
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
    /// Bumped on every SHOW: it keys the search field, so each open remounts
    /// it and `autofocus` takes the keyboard again after the hide unfocused
    /// it. The unfocus is not hygiene — a PARKED launcher with a focused
    /// field blinks its caret, and the caret ticker presents a frame per
    /// blink into a hidden window forever. Worse than the waste: a real
    /// CLICK's show-frame could not preempt that present cadence, which was
    /// the ~450ms click-to-Start stall (a quiet toggle's could — the
    /// foreground grant differs). No focus, no ticker: the parked engine is
    /// truly idle, and the show is an after-idle frame, which fires
    /// immediately.
    private var openGeneration = 0
    /// Whether the launcher has ever been shown. The field autofocuses only
    /// from then on — at PARK time (process start, hidden) focus would start
    /// the caret ticker with nobody watching. Embedded (`--oneview`) mounts
    /// only when shown, so it starts true there.
    private var everShown = false
    /// Whether the search field holds the keyboard, via its own
    /// onFocusChanged — the guard that keeps the hide-time unfocus from
    /// stealing focus some OTHER surface's field holds in a shared-process
    /// shell (the desktop's inline rename, in --oneshell).
    private var searchFocused = false

    override func initState() {
        super.initState()
        // The embedded (--oneview) launcher mounts only when it is shown, so
        // its field autofocuses from the first build; the parked modes stay
        // unfocused until their first show (see everShown).
        everShown = (widget as! StarlingLauncher).embedded
        CupertinoIcons.registerFont()
        // The chrome glyphs are Segoe Fluent Icons now; Cupertino stays
        // registered for anything the framework's own controls draw.
        FluentIcons.registerFont()

        // A notification, not a request: the WINDOW side does the showing.
        // As its own process the host owns the overlay window; as a surface
        // view (--oneshell) flwin32_surface.c owns it, and its notification
        // carries the new visibility — a hidden VIEW still composites there,
        // so unlike the process world this code has already run before the
        // first show.
        let launcher = widget as! StarlingLauncher
        if launcher.embedded {
            // A layer of the dock's tree: the dock owns visibility and the
            // bloc's opened/closed. Registering the host's onToggle from
            // here would CLOBBER the dock's own registration — one slot.
        } else if let sid = launcher.surfaceId {
            Win32Surfaces.onToggle(sid) { [weak self] visible in
                self?.didToggle(shown: visible)
            }
        } else {
            Win32WindowedHost.host?.onToggle { [weak self] in
                self?.didToggle(
                    shown: Win32WindowedHost.host?.isVisible == true)
            }
        }
        // Start's glass follows the system theme; a parked overlay still
        // receives the WM_SETTINGCHANGE broadcast, so the restyle has
        // happened by the time it is next shown.
        Win32WindowedHost.host?.onThemeChange { [weak self] in
            self?.bloc.add(.themeChanged(dark: Win32Control.isDarkMode))
        }
    }

    override func dispose() {
        // NOT icons.releaseAll(): the cache belongs to the bloc and outlives
        // this state, so releasing here would throw away the very thing that
        // was prepared at process start.
        super.dispose()
    }

    // MARK: - Showing and hiding

    private func didToggle(shown: Bool) {
        flwin32_trace("launcher: didToggle begin")
        if shown {
            // Remount the search field so autofocus takes the keyboard again
            // (the hide below unfocused it — see openGeneration's comment).
            setState {
                everShown = true
                openGeneration &+= 1
            }
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
        // Give up the keyboard, and with it the caret ticker: a parked
        // launcher must present NOTHING, or the next click-to-open waits on
        // the blink cadence (the ~450ms stall). Guarded so a shared-process
        // shell never steals focus a different surface's field holds.
        if searchFocused {
            FocusManager.instance.focusedNode?.unfocus()
        }
        bloc.add(.closed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Win32WindowedHost.host?.requestRedraw()
            flwin32_trace("launcher: hidden redraw pushed")
        }
        flwin32_trace("launcher: didToggle end (hidden)")
    }

    /// Gets Start out of the way, whichever thing is hosting it: the dock's
    /// layer (ask the dock), a surface view (hide that window), or its own
    /// process window (hide the host). The host hide is LAST — in the other
    /// two modes "the host" is the dock's panel, and hiding it takes the
    /// whole chrome off the screen.
    private func dismissSurface() {
        let launcher = widget as! StarlingLauncher
        if let close = launcher.onRequestClose {
            close()
        } else if let sid = launcher.surfaceId {
            Win32Surfaces.setVisible(sid, false)
        } else {
            Win32WindowedHost.host?.setVisible(false)
        }
    }

    private func launch(_ app: Win32App) {
        // HIDE FIRST. Starting an app is not instant even on the fast path,
        // and it is a synchronous shell call on this thread — so launching
        // first left the launcher sitting on screen, frozen, until it
        // returned. Getting out of the way is the part the user is waiting
        // for; the app arriving is the part they expect to take a moment.
        dismissSurface()
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
                            MacosIcon(icon: isPinned ? FluentIcons.removeFrom
                                                     : FluentIcons.addTo,
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
                MacosIcon(icon: FluentIcons.appDefault,
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
                                                  ? FluentIcons.removeFrom
                                                  : FluentIcons.addTo,
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
        dismissSurface()
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
                                    MacosIcon(icon: FluentIcons.power,
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
        case .lock: return FluentIcons.lock
        case .signOut: return FluentIcons.signOut
        case .sleep: return FluentIcons.moon
        case .restart: return FluentIcons.restart
        case .shutDown: return FluentIcons.power
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
                                              ? FluentIcons.chevronRight
                                              : FluentIcons.chevronDown,
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
                                MacosIcon(icon: FluentIcons.edit,
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
                key: ValueKey(openGeneration),
                controller: search,
                placeholder: "Search for apps and files",
                prefix: Padding(padding: EdgeInsets(left: 6, top: 0, right: 0, bottom: 0)) {
                    MacosIcon(icon: FluentIcons.search,
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
                // nothing at all. NOT at park time though: a hidden field's
                // focus runs the caret ticker into an invisible window (see
                // openGeneration), so focus starts with the first show.
                autofocus: everShown,
                onFocusChanged: { [weak self] focused in
                    self?.searchFocused = focused
                })
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
        let maxRows = kPinnedRows
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

    /// The letter in the account disc.
    private var initial: String {
        let name = bloc.state.userName
        guard let first = name.first else { return "?" }
        return String(first).uppercased()
    }

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

    private func pinnedHeader() -> Widget {
        // No "All apps ›" any more: everything installed is further down this
        // same scroll, so there is nowhere for that button to go. What stays
        // on the right is the pin editor, which is ours — Windows puts
        // pinning behind a right-click, and this framework gives us taps.
        sectionRow("Pinned",
                   pill(bloc.state.editingPins ? "Done" : "Pin apps",
                        bloc.state.editingPins ? FluentIcons.check : FluentIcons.pinned,
                        bloc.state.editingPins) {
                       self.bloc.add(.toggleEditPins)
                   })
    }

    /// "All … View: Category ⌄", or "‹ Utilities" once a card is open.
    private func allHeader() -> Widget {
        if let key = bloc.state.expandedGroup,
           let group = (bloc.cardGroups + bloc.groups).first(where: { $0.key == key }) {
            return sectionRow(group.name,
                              pill("Back", FluentIcons.chevronLeft, false, leading: true) {
                                  self.bloc.add(.expandGroup(nil))
                              })
        }
        let category = bloc.state.allView == .category
        return sectionRow("All",
                          pill(category ? "View: Category" : "View: List",
                               FluentIcons.chevronDown, false) {
                              self.bloc.add(.setAllView(category ? .list : .category))
                          })
    }

    /// One category card: a 2 x 2 preview of what is inside, the name under
    /// it, and a tap that opens the category in place.
    private func categoryCard(_ group: LauncherGroup) -> Widget {
        let preview = Array(group.apps.prefix(4))
        return GestureDetector(
            onTap: { self.bloc.add(.expandGroup(group.key)) },
            child: SizedBox(width: kCategoryCard + kCategoryGap,
                            height: kCategoryCardH + 34) {
                Column(mainAxisSize: .min, crossAxisAlignment: .center) {
                    SizedBox(width: kCategoryCard, height: kCategoryCardH) {
                        ClipRRect(borderRadius: BorderRadius.circular(8)) {
                            ColoredBox(color: theme.fieldFill) {
                                Center {
                                    Column(mainAxisSize: .min,
                                           crossAxisAlignment: .center) {
                                        for pair in [Array(preview.prefix(2)),
                                                     Array(preview.dropFirst(2))]
                                        where !pair.isEmpty {
                                            Row(mainAxisSize: .min,
                                                crossAxisAlignment: .center) {
                                                for app in pair {
                                                    SizedBox(width: 56, height: 56) {
                                                        Center {
                                                            appIcon(IconCache.key(for: app), 34)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    SizedBox(height: 8)
                    SizedBox(width: kCategoryCard, height: 20) {
                        Center {
                            Text(group.name,
                                 style: TextStyle(color: theme.text, fontSize: 12),
                                 overflow: .ellipsis, maxLines: 1)
                        }
                    }
                }
            })
    }

    private func categoryRow(_ groups: [LauncherGroup]) -> Widget {
        SizedBox(width: kStartContent, height: kCategoryCardH + 44) {
            Row(mainAxisAlignment: .start, mainAxisSize: .min) {
                for group in groups { categoryCard(group) }
            }
        }
    }

    /// The whole panel as ONE list: the pinned grid and every app installed,
    /// in the order Start shows them. Built as descriptors rather than widgets so the
    /// list stays lazy — 129 apps is 129 rows in the list view.
    private var startRows: [StartRow] {
        var rows: [StartRow] = [.pinnedHeader, .pinnedGrid, .gap(22), .allHeader]
        let cards = bloc.state.allView == .category ? bloc.cardGroups : []
        let groups = bloc.groups
        if let key = bloc.state.expandedGroup,
           let group = (cards + groups).first(where: { $0.key == key }) {
            rows += group.apps.map { .app($0) }
        } else if bloc.state.allView == .category {
            var index = 0
            while index < cards.count {
                let end = min(index + kCategoryColumns, cards.count)
                rows.append(.categoryCards(Array(cards[index..<end])))
                index = end
            }
        } else {
            for group in groups {
                rows.append(.groupHeader(group))
                if !group.collapsed { rows += group.apps.map { .app($0) } }
            }
        }
        rows.append(.gap(20))
        return rows
    }

    private func startRow(_ row: StartRow) -> Widget {
        switch row {
        case .pinnedHeader:      return pinnedHeader()
        case .pinnedGrid:        return pinnedGrid()
        case .allHeader:         return allHeader()
        case .categoryCards(let groups): return categoryRow(groups)
        case .groupHeader(let group):    return groupHeader(group)
        case .app(let app):      return appRow(app, indented: true)
        case .gap(let h):        return SizedBox(width: kStartContent, height: h)
        }
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
                    } else {
                        // ONE scroll: the pinned grid and every app
                        // installed, the way Start stacks them once
                        // Recommended is turned off. The list is keyed by what shape its
                        // rows are, because a lazy list whose cells change
                        // TYPE keeps painting the old ones inside the new
                        // extents (the trap is in the SDK's CLAUDE.md).
                        let rows = startRows
                        Expanded {
                            SizedBox(width: kStartContent) {
                                ListView(
                                    key: ValueKey("start-\(bloc.state.allView)-"
                                                  + (bloc.state.expandedGroup ?? "")),
                                    controller: scroll,
                                    itemCount: rows.count,
                                    itemBuilder: { [weak self] _, index in
                                        guard let self, index < rows.count else {
                                            return SizedBox(height: 0)
                                        }
                                        return self.startRow(rows[index])
                                    })
                            }
                        }
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
