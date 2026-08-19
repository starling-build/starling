// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The dock, on Windows — and the whole of the shell's chrome.
//
// It started beside a menu bar along the top, macOS-shaped, and that was one
// surface too many: Windows puts its shell chrome on the bottom edge, and two
// strips to reach for is worse than one wherever they sit. So the bar is gone
// and this covers the taskbar it replaces — the launcher where Start was, the
// running apps in the middle, the clock and the status icons at the right.
//
// It is a FULL-WIDTH BAR, not a floating slab. The slab was the macOS shape
// and it left wallpaper showing on both sides of a strip that Windows fills
// edge to edge; the icons are still centred, Windows 11 style, but the bar
// under them now runs the width of the screen.
//
// The panel is still declared `transparent`, and that is no longer about the
// look: the colour key is what makes the OVERHANG a hole. The window has to
// extend above the strip for the hover label and the right-click menu to have
// somewhere to draw (a window is a hard clip), and without the key that would
// be a 190pt opaque band standing over the desktop. The strip itself is
// opaque, so nothing about the bar is see-through.
//
// Clicking a tile raises its app, or starts it; right-clicking pins or unpins
// it; hovering names it; a running indicator sits under each.
//
// Where the apps come from is the interesting part. The Linux shell reads
// Starling's own registry; Windows has none, so `Win32AppCatalog` reads the
// START MENU — the same tree Explorer's Start reads — and that is the
// catalog behind both this and the launcher.

#if os(Windows)
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import Foundation

/// Bar height in logical points, and the icon size inside it.
///
/// Sized against Windows' own taskbar (48pt) rather than against a macOS
/// dock: a floating slab can afford to be tall because wallpaper surrounds
/// it, and a solid strip across the screen cannot.
let kDockHeight = 56
let kDockIcon = 34.0

/// How far the dock's WINDOW extends above the strip it reserves. The hover
/// label, the right-click menu and the control centre all draw in here; a
/// window is a hard clip, so without it they would be cut off at the top of
/// the strip. It reserves nothing and is transparent, so it is invisible and
/// click-through until something paints. Tall enough for the control centre,
/// which is the largest thing that opens here.
let kDockOverhang = 300

/// Geometry the flyout arithmetic needs. The tile is a fixed size, so where
/// each one sits is arithmetic rather than a layout query — which is what
/// lets a label be positioned over an icon without measuring anything.
let kDockTile = kDockIcon + 14.0

/// The control centre, in logical points. The tile grid is two columns wide
/// and the panel is sized from it rather than the other way round, so a
/// change to the tile size cannot leave the panel the wrong width.
let kCcPad = 10.0
let kCcGap = 8.0
let kCcTileW = 138.0
let kCcTileH = 62.0
let kCcSliderH = 40.0
let kCcRowH = 32.0
let kCcWidth = kCcTileW * 2 + kCcGap + kCcPad * 2
let kCcHeight = kCcPad * 2 + kCcTileH * 2 + kCcGap + kCcSliderH + kCcRowH + kCcGap
/// How far the panel sits from the right edge and above the strip.
let kCcInset = 12.0

/// Width of the status cluster. FIXED, and imposed with a SizedBox, for the
/// same reason the dock's tiles are a fixed size: the click that opens the
/// control centre is hit-tested by arithmetic from a root Listener, and an
/// estimate that drifts from the layout opens the panel from the wrong place
/// — or from nowhere.
let kStatusWidth = 210.0

/// Gap between tiled windows, in logical points — scaled to pixels at use,
/// because window geometry is the one place this file speaks physical. It is
/// applied on every edge, so adjacent windows are two gaps apart, the same
/// convention the Linux shell's tiler uses.
let kTileGap = 8

/// Whether Explorer's taskbar is left alone. `--plain` is a bisect flag and
/// has no business changing the desktop underneath it.
let keepsNativeTaskbar =
    CommandLine.arguments.contains("--keep-taskbar")
    || CommandLine.arguments.contains("--plain")

/// What the dock keeps when nothing of that app is running, on a machine that
/// has never been told otherwise. Matched loosely against the Start Menu
/// name, because the exact wording moves between Windows releases ("Command
/// Prompt" vs "Terminal") and a dock that silently loses an entry after an
/// update is worse than one that keeps a near match.
let kDefaultPins = ["file explorer", "terminal", "notepad", "paint", "edge", "settings"]

/// The launcher's tile. A reserved key rather than a separate widget, so it
/// flows through the same hit-testing arithmetic, the same hover label and
/// the same layout as every other tile — a dock with one special-cased tile
/// on the left is where the geometry starts drifting.
///
/// It lives here, not on the menu bar, because that is where a launcher goes
/// on a macOS-shaped desktop: the top strip belongs to the focused app, and
/// the thing you press to start something belongs beside the things you have
/// already started.
let kLauncherKey = "\u{1}starling-launcher"

/// One dock entry: an installed app, a running app, or both.
struct DockItem {
    let key: String
    let name: String
    /// nil for something running that we could not find in the Start Menu —
    /// it still shows and still raises, it just cannot be launched again.
    let app: Win32App?
    /// Every window this app has, most recently used first.
    let windows: [Win32Window]
    let isPinned: Bool
    var isRunning: Bool { !windows.isEmpty }
    var isForeground: Bool { windows.contains { $0.isForeground } }
}

final class StarlingDock: StatefulWidget {
    override func createState() -> State<StatefulWidget> { StarlingDockState() }
}

final class StarlingDockState: State<StatefulWidget> {
    private let icons = IconCache()
    private var items: [DockItem] = []
    /// The Start Menu, read once. It is a few hundred COM round trips, so it
    /// is not something to redo on a window opening; an app installed while
    /// the dock runs appears at the next explicit rescan.
    private var catalog: [Win32App] = []
    private var refreshQueued = false

    /// Pinned apps, by the same key the icon cache uses, in the order the
    /// user put them. Persisted — a dock that forgets what you pinned every
    /// time you log out is a dock you stop pinning things to.
    private var pins: [String] = []
    /// Which tile the pointer is over, and which one has a menu open. Index
    /// into `items`, or nil.
    private var hovered: Int?
    private var menuOpen: Int?

    // The clock and the status cluster, which used to live on the menu bar.
    // Polled on one timer rather than subscribed: each of the three has its
    // own notification mechanism, they deliver on three different threads,
    // and a status readout that updates a second late is indistinguishable
    // from one that does not.
    private var now = Date()
    private var timer: AnyObject?
    private var network = Win32Network(kind: .none, signal: 0, ssid: "")
    private var power = Win32Power(hasBattery: false, percent: nil, isCharging: true)
    private var volume: Win32Volume?
    /// Set from the control centre: while it is on, the re-assert below stands
    /// down so "Show Windows Taskbar" stays shown.
    private var nativeTaskbarWanted = false

    /// Whether the control centre is down, and whether the pointer is
    /// currently dragging its volume slider.
    private var controlCentreOpen = false
    private var draggingVolume = false
    private var darkMode = Win32Control.isDarkMode
    /// Set by the Wi-Fi tile so the panel answers the click immediately —
    /// the radio takes a moment to settle and the next poll is a second
    /// away, which without this reads as a dead button.
    private var wifiWanted: Bool?

    override func initState() {
        super.initState()
        CupertinoIcons.registerFont()
        catalog = Win32AppCatalog.apps()
        pins = loadPins()
        print("[WinShellDock] \(catalog.count) apps in the Start Menu, \(pins.count) pinned")
        rebuild()
        readStatus()
        Win32WindowManager.observe { [weak self] _ in self?.queueRefresh() }

        // Through hostPeriodicTimerInstall rather than Foundation.Timer: on
        // the DRM embedder a Foundation timer never fires at all (see the
        // desktop's CLAUDE.md), and going through the host keeps every
        // backend honest about which loop the UI thread is really running.
        timer = startPeriodicTimer(seconds: 1.0) { [weak self] in
            guard let self else { return }
            // Explorer puts its taskbar back on its own — a display change, a
            // Settings round-trip, or explorer restarting after a crash all
            // do it, and none of them tell us. The EVENT_OBJECT_SHOW hook
            // catches the fast case; this catches a new explorer pid.
            if !keepsNativeTaskbar && !self.nativeTaskbarWanted
                && Win32Shell.nativeTaskbarIsVisible {
                Win32Shell.hideNativeTaskbar()
            }
            setState {
                self.now = Date()
                self.readStatus()
            }
        }
    }

    override func dispose() {
        Win32WindowManager.stopObserving()
        icons.releaseAll()
        super.dispose()
    }

    private func readStatus() {
        network = Win32Status.network()
        power = Win32Status.power()
        volume = Win32Status.volume()
        // The poll is the truth. Drop the optimistic Wi-Fi answer as soon as
        // it agrees, so a radio that refused the change corrects itself
        // instead of leaving the tile lying about it.
        if let wanted = wifiWanted, (network.kind == .wifi) == wanted { wifiWanted = nil }
        // Read rather than remembered: the user can change the theme in
        // Windows' own Settings and the tile has to follow.
        darkMode = Win32Control.isDarkMode
    }

    // MARK: - Pins, on disk

    /// `%APPDATA%\Starling\dock.txt`, one target per line. A text file rather
    /// than the registry: it is inspectable, it is trivially resettable by
    /// deleting it, and a shell prototype has no business writing to HKCU.
    private var pinsPath: String {
        let base = ProcessInfo.processInfo.environment["APPDATA"]
            ?? ProcessInfo.processInfo.environment["USERPROFILE"] ?? "."
        return base + "\\Starling\\dock.txt"
    }

    private func loadPins() -> [String] {
        guard let text = try? String(contentsOfFile: pinsPath, encoding: .utf8) else {
            // First run: seed from the defaults, resolved against what is
            // actually installed, so the dock is never empty on a new machine.
            return kDefaultPins.compactMap { wanted in
                catalog.first(where: { $0.name.lowercased().contains(wanted) })
                    .map { IconCache.key(for: $0) }
            }
        }
        return text.split(whereSeparator: { $0 == "\r\n" || $0 == "\n" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func savePins() {
        let directory = (pinsPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        try? pins.joined(separator: "\r\n").write(
            toFile: pinsPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Model

    private func queueRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            refreshQueued = false
            setState { self.rebuild() }
        }
    }

    /// Pinned apps first, in the order the user pinned them, then whatever
    /// else is running. Deliberately stable: an entry must not move out from
    /// under the pointer when an unrelated window opens.
    private func rebuild() {
        let windows = Win32WindowManager.windows()
        var byExe: [String: [Win32Window]] = [:]
        for window in windows {
            byExe[IconCache.key(for: window), default: []].append(window)
        }

        var built: [DockItem] = []
        var claimed: Set<String> = []

        for key in pins {
            guard !claimed.contains(key) else { continue }
            claimed.insert(key)
            let app = catalog.first(where: { IconCache.key(for: $0) == key })
            let windows = byExe[key] ?? []
            // A pin whose app is neither installed nor running is a stale
            // entry — usually an app that was uninstalled. Keep it out of the
            // dock rather than drawing a permanent blank tile.
            guard app != nil || !windows.isEmpty else { continue }
            built.append(DockItem(key: key, name: app?.name ?? windows[0].appName,
                                  app: app, windows: windows, isPinned: true))
        }

        for window in windows {
            let key = IconCache.key(for: window)
            guard !claimed.contains(key) else { continue }
            claimed.insert(key)
            let app = catalog.first(where: { IconCache.key(for: $0) == key })
            built.append(DockItem(key: key, name: app?.name ?? window.appName,
                                  app: app, windows: byExe[key] ?? [],
                                  isPinned: false))
        }

        // A running app's own window icon beats the Start Menu's: a browser's
        // window icon is the profile or the site, which is what the user is
        // actually looking at.
        for item in built {
            if let window = item.windows.first {
                icons.ensure(window: window, size: 48)
            } else if let app = item.app {
                icons.ensure(app: app)
            }
        }
        icons.retain(only: claimed)
        items = [DockItem(key: kLauncherKey, name: "Launcher", app: nil,
                          windows: [], isPinned: true)] + built
        if let open = menuOpen, open >= items.count { menuOpen = nil }
        if let over = hovered, over >= items.count { hovered = nil }
    }

    // MARK: - Actions

    /// The dock's whole interaction model, in one place. Not running: start
    /// it. Running but not focused: raise it. Focused: put it away — which is
    /// what a dock icon does everywhere else and is the reason a dock is
    /// faster than Alt+Tab for the app you keep coming back to.
    private func activate(_ item: DockItem) {
        menuOpen = nil
        // The launcher is a different PROCESS — one widget root per process —
        // so pressing it is a broadcast, not a call.
        guard item.key != kLauncherKey else {
            Win32Shell.toggleOverlay()
            return
        }
        guard let window = item.windows.first(where: { $0.isForeground })
                ?? item.windows.first else {
            if let app = item.app { Win32AppCatalog.launch(app) }
            return
        }
        if window.isForeground {
            Win32WindowManager.minimize(window.handle)
        } else {
            Win32WindowManager.activate(window.handle)
        }
        queueRefresh()
    }

    private func togglePin(_ item: DockItem) {
        if let at = pins.firstIndex(of: item.key) {
            pins.remove(at: at)
        } else {
            pins.append(item.key)
        }
        savePins()
        setState {
            self.menuOpen = nil
            self.rebuild()
        }
    }

    private func closeAll(_ item: DockItem) {
        for window in item.windows { Win32WindowManager.close(window.handle) }
        setState { self.menuOpen = nil }
        queueRefresh()
    }

    /// Lay every visible window out on a grid, per monitor.
    ///
    /// Per MONITOR, not per desktop: grouping everything into one grid drags
    /// every window onto the primary, which is a destructive answer to "tidy
    /// these up". Moved here from the menu bar, and reachable from the
    /// launcher tile's menu.
    private func tileAll() {
        let visible = items.flatMap { $0.windows }.filter { !$0.isMinimized }
        guard !visible.isEmpty else { return }

        var byMonitor: [Int: [Win32Window]] = [:]
        for window in visible {
            // A window Windows will not place on any monitor still has to go
            // somewhere; the primary is where it would have been dragged.
            byMonitor[window.monitor ?? 0, default: []].append(window)
        }
        let scales = Dictionary(uniqueKeysWithValues:
            Win32Display.monitors().map { ($0.index, $0.scale) })
        for monitor in byMonitor.keys.sorted() {
            tile(byMonitor[monitor]!, on: monitor, scale: scales[monitor] ?? 1.0)
        }
        queueRefresh()
    }

    private func tile(_ group: [Win32Window], on monitor: Int, scale: Double) {
        guard let area = Win32WindowManager.workArea(monitor: monitor) else { return }

        // Window rectangles are physical pixels — they are other people's
        // windows on other people's monitors, and there is no single logical
        // space spanning a mixed-DPI desktop. So the gap is scaled here, per
        // monitor, rather than once for the whole desktop.
        let gap = Int((Double(kTileGap) * scale).rounded())

        let columns = Int(ceil(Double(group.count).squareRoot()))
        let rows = Int(ceil(Double(group.count) / Double(columns)))
        let cellHeight = (area.height - gap * (rows + 1)) / rows

        var index = 0
        for row in 0..<rows {
            // The last row takes whatever is left and stretches across the
            // full width, rather than leaving a hole where a cell would have
            // been. Three windows tile as two over one, not two over one and
            // a gap.
            let inRow = min(columns, group.count - index)
            let cellWidth = (area.width - gap * (inRow + 1)) / inRow
            for column in 0..<inRow {
                let window = group[index]
                Win32WindowManager.move(window.handle, to: Win32Rect(
                    x: area.x + gap + column * (cellWidth + gap),
                    y: area.y + gap + row * (cellHeight + gap),
                    width: cellWidth,
                    height: cellHeight))
                index += 1
            }
        }
    }

    // MARK: - The control centre
    //
    // Clicking the status readout opens the panel that changes what it is
    // reading — the same bargain the desktop's own control centre makes, and
    // the reason the readout is worth clicking at all.
    //
    // Every rectangle in here is arithmetic, computed once by `ccRects` and
    // used by BOTH the drawing and the hit-testing. That is not a style
    // choice: this framework's widget-level input callbacks are unreliable
    // here (MouseRegion.onEnter and onSecondaryTap never fire, see
    // `pointerTile`), so the panel is driven from a root Listener, and a
    // layout that positioned its tiles independently of the hit test would
    // drift the two apart with nothing to show for it but dead buttons.

    /// One control-centre control: where it is, and what it does.
    private struct CcRect {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
        func contains(_ px: Double, _ py: Double) -> Bool {
            px >= x && px <= x + w && py >= y && py <= y + h
        }
    }

    /// The panel's own frame, in the dock window's coordinates.
    private var ccFrame: CcRect {
        let height = Double(kDockHeight + kDockOverhang)
        return CcRect(x: ShellScreen.logicalWidth - kCcInset - kCcWidth,
                      y: height - Double(kDockHeight) - kCcInset - kCcHeight,
                      w: kCcWidth, h: kCcHeight)
    }

    /// The four tiles, then the slider track, then the wide bottom row — in
    /// the order they are drawn.
    private func ccRects() -> (tiles: [CcRect], slider: CcRect, row: CcRect) {
        let f = ccFrame
        var tiles: [CcRect] = []
        for index in 0..<4 {
            tiles.append(CcRect(
                x: f.x + kCcPad + Double(index % 2) * (kCcTileW + kCcGap),
                y: f.y + kCcPad + Double(index / 2) * (kCcTileH + kCcGap),
                w: kCcTileW, h: kCcTileH))
        }
        let afterTiles = f.y + kCcPad + kCcTileH * 2 + kCcGap * 2
        // The track starts clear of the speaker glyph at its left.
        let slider = CcRect(x: f.x + kCcPad + 28, y: afterTiles,
                            w: kCcWidth - kCcPad * 2 - 28, h: kCcSliderH)
        let row = CcRect(x: f.x + kCcPad, y: afterTiles + kCcSliderH,
                         w: kCcWidth - kCcPad * 2, h: kCcRowH)
        return (tiles, slider, row)
    }

    /// Where the status readout is, and therefore what opens the panel.
    private var ccOpener: CcRect {
        let height = Double(kDockHeight + kDockOverhang)
        return CcRect(x: ShellScreen.logicalWidth - kStatusWidth,
                      y: height - Double(kDockHeight),
                      w: kStatusWidth, h: Double(kDockHeight))
    }

    /// Wi-Fi, Sound, Dark Mode, Tile Windows.
    ///
    /// Not the desktop's six: three of those (Record, Record App, Tiling as a
    /// mode) have no counterpart here yet, and a tile that does nothing is
    /// worse than a tile that is missing.
    private func ccTapped(_ index: Int) {
        switch index {
        case 0:
            let on = !wifiIsOn
            // Optimistic, then corrected by the next poll — see wifiWanted.
            wifiWanted = on
            if !Win32Control.setWifiRadio(on) { wifiWanted = nil }
        case 1:
            let muted = !(volume?.isMuted ?? false)
            Win32Control.setMuted(muted)
            volume = Win32Volume(percent: volume?.percent ?? 0, isMuted: muted)
        case 2:
            darkMode.toggle()
            Win32Control.setDarkMode(darkMode)
        default:
            controlCentreOpen = false
            tileAll()
        }
    }

    /// What the Wi-Fi tile should show. The poll is the truth; `wifiWanted`
    /// covers the second between the click and the radio settling.
    private var wifiIsOn: Bool { wifiWanted ?? (network.kind == .wifi) }

    private func ccSetVolumeFrom(_ x: Double) {
        let track = ccRects().slider
        let fraction = min(1, max(0, (x - track.x) / track.w))
        let percent = Int((fraction * 100).rounded())
        volume = Win32Volume(percent: percent, isMuted: percent == 0)
        Win32Control.setVolume(percent)
    }

    private func ccTile(_ index: Int, icon: IconData, label: String,
                        active: Bool, available: Bool = true) -> Widget {
        let rect = ccRects().tiles[index]
        let fill = !available ? Color(0x14FFFFFF)
            : active ? Color(0xFF2F6FE0) : Color(0x1FFFFFFF)
        let ink = available ? Color(0xFFF2F5FA) : Color(0xFF6E7683)
        return Positioned(left: rect.x - ccFrame.x, top: rect.y - ccFrame.y) {
            SizedBox(width: rect.w, height: rect.h) {
                ClipRRect(borderRadius: BorderRadius.circular(10)) {
                    ColoredBox(color: fill) {
                        Padding(padding: EdgeInsets(left: 12, top: 0, right: 10, bottom: 0)) {
                            Row(crossAxisAlignment: .center, spacing: 10) {
                                MacosIcon(icon: icon, color: ink, size: 19)
                                Expanded {
                                    Text(label,
                                         style: TextStyle(color: ink, fontSize: 12,
                                                          fontWeight: .w500),
                                         overflow: .ellipsis, maxLines: 1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The volume slider, drawn rather than composed.
    ///
    /// A `MacosSlider` would want a pan recognizer, and recognizers are
    /// exactly what does not arrive reliably in this surface — so the track,
    /// the fill and the knob are three boxes and the drag is two lines in the
    /// root Listener. It also keeps the slider's geometry in `ccRects`, where
    /// the hit test can see it.
    private func ccSlider() -> Widget {
        let rect = ccRects().slider
        let percent = Double(volume?.percent ?? 0)
        let fraction = min(1, max(0, percent / 100))
        let knob = (rect.w - 14) * fraction
        return Positioned(left: kCcPad, top: rect.y - ccFrame.y) {
            SizedBox(width: kCcWidth - kCcPad * 2, height: rect.h) {
                Stack(alignment: Alignment.centerLeft) {
                    Align(alignment: Alignment.centerLeft) {
                        MacosIcon(icon: (volume?.isMuted ?? false)
                                      ? CupertinoIcons.speaker_slash
                                      : CupertinoIcons.speaker_2,
                                  color: Color(0xFFD5DAE3), size: 16)
                    }
                    Positioned(left: 28, top: rect.h / 2 - 3, width: rect.w, height: 6) {
                        ClipRRect(borderRadius: BorderRadius.circular(3)) {
                            ColoredBox(color: Color(0x33FFFFFF)) { SizedBox(expand: ()) }
                        }
                    }
                    Positioned(left: 28, top: rect.h / 2 - 3,
                               width: max(6, knob + 7), height: 6) {
                        ClipRRect(borderRadius: BorderRadius.circular(3)) {
                            ColoredBox(color: Color(0xFF4C8DF6)) { SizedBox(expand: ()) }
                        }
                    }
                    Positioned(left: 28 + knob, top: rect.h / 2 - 7, width: 14, height: 14) {
                        ClipRRect(borderRadius: BorderRadius.circular(7)) {
                            ColoredBox(color: Color(0xFFF2F5FA)) { SizedBox(expand: ()) }
                        }
                    }
                }
            }
        }
    }

    private func ccBottomRow() -> Widget {
        let rect = ccRects().row
        return Positioned(left: kCcPad, top: rect.y - ccFrame.y) {
            SizedBox(width: rect.w, height: rect.h) {
                ClipRRect(borderRadius: BorderRadius.circular(8)) {
                    ColoredBox(color: Color(0x14FFFFFF)) {
                        Padding(padding: EdgeInsets(left: 12, top: 0, right: 12, bottom: 0)) {
                            Row(crossAxisAlignment: .center, spacing: 10) {
                                MacosIcon(icon: CupertinoIcons.rectangle_grid_2x2,
                                          color: Color(0xFFD5DAE3), size: 15)
                                Expanded {
                                    Text(nativeTaskbarWanted
                                             ? "Hide the Windows taskbar"
                                             : "Show the Windows taskbar",
                                         style: TextStyle(color: Color(0xFFD5DAE3), fontSize: 12),
                                         overflow: .ellipsis, maxLines: 1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// A press while the panel is open. Returns true if the panel consumed it.
    ///
    /// Consuming matters: a press that lands on the panel must not also reach
    /// whatever is behind it, and a press outside must close the panel while
    /// still letting a dock tile take the same click.
    private func handleControlCentre(_ x: Double, _ y: Double) -> Bool {
        let rects = ccRects()
        if rects.slider.contains(x, y) {
            setState {
                draggingVolume = true
                ccSetVolumeFrom(x)
            }
            return true
        }
        if rects.row.contains(x, y) {
            setState {
                nativeTaskbarWanted.toggle()
                controlCentreOpen = false
            }
            if nativeTaskbarWanted {
                Win32Shell.showNativeTaskbar()
            } else {
                Win32Shell.hideNativeTaskbar()
            }
            return true
        }
        for (index, tile) in rects.tiles.enumerated() where tile.contains(x, y) {
            setState { ccTapped(index) }
            return true
        }
        // Inside the panel but on nothing: swallow it, so a click on the
        // panel's own background does not close it.
        if ccFrame.contains(x, y) { return true }
        // Outside: close, and let the press carry on to whatever it hit.
        setState { controlCentreOpen = false }
        return false
    }

    private func controlCentre() -> Widget {
        let frame = ccFrame
        let height = Double(kDockHeight + kDockOverhang)
        return Positioned(left: frame.x, bottom: height - (frame.y + frame.h)) {
            SizedBox(width: frame.w, height: frame.h) {
                ClipRRect(borderRadius: BorderRadius.circular(14)) {
                    ColoredBox(color: Color(0xF41F2229)) {
                        Stack(alignment: Alignment.topLeft) {
                            ccTile(0,
                                   icon: wifiIsOn ? CupertinoIcons.wifi : CupertinoIcons.wifi_slash,
                                   label: network.kind == .ethernet && wifiWanted == nil
                                       ? "Ethernet" : (wifiIsOn ? "Wi-Fi" : "Wi-Fi off"),
                                   active: wifiIsOn || network.kind == .ethernet,
                                   // No radio to switch: the tile says so
                                   // rather than pretending to be off.
                                   available: network.kind == .wifi || wifiWanted != nil)
                            ccTile(1,
                                   icon: (volume?.isMuted ?? false)
                                       ? CupertinoIcons.speaker_slash : CupertinoIcons.speaker_2,
                                   label: (volume?.isMuted ?? false) ? "Muted" : "Sound",
                                   active: !(volume?.isMuted ?? false),
                                   available: volume != nil)
                            ccTile(2, icon: CupertinoIcons.moon_fill, label: "Dark Mode",
                                   active: darkMode)
                            ccTile(3, icon: CupertinoIcons.square_grid_2x2,
                                   label: "Tile Windows", active: false)
                            ccSlider()
                            ccBottomRow()
                        }
                    }
                }
            }
        }
    }

    // MARK: - The status cluster
    //
    // Read from the system (`Win32Status`), not drawn: a shell with a fixed
    // wifi glyph and a fixed battery glyph is a picture of a status bar. All
    // three moved down here when the menu bar went away, because this is
    // where Windows keeps them and where the user will look.

    private func clockText() -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm  EEE d MMM"
        return f.string(from: now)
    }

    /// Wi-Fi with a slash when nothing is connected, and the aerial glyph for
    /// Ethernet — a wifi symbol on a desk machine is a lie the user cannot
    /// correct. Signal is shown as a colour rather than as bars: the icon
    /// font has one wifi glyph, and a faded one reads as weak without
    /// inventing a bar chart.
    private func networkIcon() -> Widget {
        let icon: IconData
        let colour: Color
        switch network.kind {
        case .none:
            icon = CupertinoIcons.wifi_slash
            colour = Color(0xFF6E7683)
        case .ethernet:
            icon = CupertinoIcons.antenna_radiowaves_left_right
            colour = Color(0xFFD5DAE3)
        case .wifi:
            icon = CupertinoIcons.wifi
            colour = network.signal >= 60 ? Color(0xFFD5DAE3)
                : network.signal >= 30 ? Color(0xFFB0B7C3) : Color(0xFF7F8794)
        }
        return MacosIcon(icon: icon, color: colour, size: 15)
    }

    private func volumeIcon() -> Widget? {
        guard let volume else { return nil }
        let icon: IconData = volume.isMuted ? CupertinoIcons.speaker_slash
            : volume.percent == 0 ? CupertinoIcons.speaker
            : volume.percent < 34 ? CupertinoIcons.speaker_1
            : volume.percent < 67 ? CupertinoIcons.speaker_2
            : CupertinoIcons.speaker_3
        return MacosIcon(icon: icon,
                         color: volume.isMuted ? Color(0xFF6E7683) : Color(0xFFD5DAE3),
                         size: 15)
    }

    /// Nothing at all on a desktop. An empty battery outline on a machine
    /// with no battery is worse than no icon: it reads as "flat".
    private func batteryWidgets() -> [Widget] {
        guard power.hasBattery else { return [] }
        let icon: IconData = power.isCharging ? CupertinoIcons.battery_charging
            : (power.percent ?? 100) <= 10 ? CupertinoIcons.battery_empty
            : (power.percent ?? 100) <= 40 ? CupertinoIcons.battery_25
            : CupertinoIcons.battery_full
        var out: [Widget] = [
            MacosIcon(icon: icon,
                      color: (power.percent ?? 100) <= 10 && !power.isCharging
                          ? Color(0xFFFF6B6B) : Color(0xFFD5DAE3),
                      size: 17)
        ]
        if let percent = power.percent {
            out.append(Text("\(percent)%",
                            style: TextStyle(color: Color(0xFFB0B7C3), fontSize: 12)))
        }
        return out
    }

    /// The status readout, at the right end of the bar — where Windows keeps
    /// its clock and where a user will look for one. Plain on the strip now
    /// rather than in a slab of its own: the strip is opaque and full width,
    /// so there is nothing for a second slab to separate it from.
    private func statusCluster() -> Widget {
        // A fixed width, imposed rather than measured — `ccOpener` hit-tests
        // against this same number, and a readout that laid itself out to its
        // content would drift away from the rectangle that opens the panel.
        SizedBox(width: kStatusWidth, height: Double(kDockHeight)) {
        Padding(padding: EdgeInsets(left: 0, top: 0, right: 16, bottom: 0)) {
            Row(mainAxisAlignment: .end, crossAxisAlignment: .center, spacing: 9) {
                if let speaker = volumeIcon() { speaker }
                networkIcon()
                for widget in batteryWidgets() { widget }
                Padding(padding: EdgeInsets(left: 4, top: 0, right: 0, bottom: 0)) {
                    Text(clockText(),
                         style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 13))
                }
            }
        }
        }
    }

    // MARK: - Geometry

    /// Which tile a point in the panel is over, or nil.
    ///
    /// Hit-tested by ARITHMETIC, from a Listener at the root, because the two
    /// widget-level routes both come up empty on this framework:
    /// `MouseRegion.onEnter`/`onExit` never fire, and `onSecondaryTap` never
    /// fires either — even though the raw events are demonstrably arriving
    /// (a root Listener sees `hover` and sees `down buttons=2`). Recognizers
    /// and mouse-tracker annotations are the missing link, not the host. The
    /// tile is a fixed size and the row is centred, so doing it here costs
    /// four lines and no layout query.
    private func pointerTile(_ x: Double, _ y: Double) -> Int? {
        guard !items.isEmpty else { return nil }
        // The strip is the bottom kDockHeight of the window; everything above
        // it is the overhang, which is a hole.
        let stripTop = Double(kDockOverhang)
        guard y >= stripTop else { return nil }

        let left = rowLeft()
        let index = Int((x - left) / kDockTile)
        guard x >= left, index >= 0, index < items.count else { return nil }
        return index
    }

    /// Where the centred row of tiles starts, in the panel's own coordinates.
    ///
    /// `ShellScreen`, not `Win32Display.primary()`: the width has to be the
    /// width of the screen this bar is ON, and it has to follow a resolution
    /// change — the host re-places the strip on WM_DISPLAYCHANGE and the
    /// icons have to be centred on the new one.
    private func rowLeft() -> Double {
        (ShellScreen.logicalWidth - Double(items.count) * kDockTile) / 2
    }

    /// Where a tile's centre sits. The tile is a fixed size and the row is
    /// centred, so this is arithmetic — no measuring, which is what lets a
    /// flyout be positioned over an icon without a layout pass to ask where
    /// it ended up.
    private func tileCentre(_ index: Int) -> Double {
        rowLeft() + Double(index) * kDockTile + kDockTile / 2
    }

    // MARK: - Build

    private func tile(_ item: DockItem, _ index: Int) -> Widget {
        // Only the primary tap lives on the tile. Hover and the right-click
        // menu are driven from a Listener at the root instead — see the note
        // on `pointerTile`.
        GestureDetector(
                onTap: { self.activate(item) },
                child: Padding(padding: EdgeInsets(left: 7, top: 0, right: 7, bottom: 0)) {
                    Column(mainAxisSize: .min, crossAxisAlignment: .center) {
                        if item.key == kLauncherKey {
                            SizedBox(width: kDockIcon, height: kDockIcon) {
                                ClipRRect(borderRadius: BorderRadius.circular(10)) {
                                    ColoredBox(color: Color(0xFF2B3550)) {
                                        Center {
                                            MacosIcon(icon: CupertinoIcons.square_grid_2x2,
                                                      color: Color(0xFF9EC2FF), size: 21)
                                        }
                                    }
                                }
                            }
                        } else if let icon = icons.view(item.key, side: kDockIcon) {
                            icon
                        } else {
                            SizedBox(width: kDockIcon, height: kDockIcon) {
                                Center {
                                    MacosIcon(icon: CupertinoIcons.app_badge,
                                              color: Color(0xFFB8C0CC), size: 21)
                                }
                            }
                        }
                        // The running indicator: one dot per window, up to
                        // three, brighter when the app has focus. A dot
                        // rather than a highlight behind the icon, so the
                        // app's own artwork stays the thing the eye lands on
                        // — and counting them is how a glance tells four
                        // documents from one.
                        SizedBox(height: 7) {
                            Center {
                                Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 3) {
                                    for _ in 0..<min(item.windows.count, 3) {
                                        ClipRRect(borderRadius: BorderRadius.circular(2.5)) {
                                            ColoredBox(color: item.isForeground
                                                ? Color(0xFFFFFFFF) : Color(0x99FFFFFF)) {
                                                SizedBox(width: 5, height: 5)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                })
    }

    /// The hover label. Drawn in the overhang, above the strip.
    private func label(_ index: Int) -> Widget {
        let item = items[index]
        // Rough, because the text is not measured: enough to keep a long name
        // roughly centred over its icon rather than hanging off one side.
        let width = Double(item.name.count) * 6.6 + 20
        return Positioned(
            left: max(4, tileCentre(index) - width / 2),
            bottom: Double(kDockHeight) + 6,
            child: ClipRRect(borderRadius: BorderRadius.circular(6)) {
                ColoredBox(color: Color(0xF01B1D22)) {
                    Padding(padding: EdgeInsets(left: 10, top: 5, right: 10, bottom: 5)) {
                        Text(item.name,
                             style: TextStyle(color: Color(0xFFE6EAF0), fontSize: 12),
                             maxLines: 1)
                    }
                }
            })
    }

    private func menuRow(_ text: String, _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: action,
            child: SizedBox(width: 168, height: 30) {
                Padding(padding: EdgeInsets(left: 12, top: 0, right: 12, bottom: 0)) {
                    Align(alignment: Alignment.centerLeft) {
                        Text(text, style: TextStyle(color: Color(0xFFE6EAF0), fontSize: 12))
                    }
                }
            })
    }

    /// The right-click menu, also in the overhang.
    private func menu(_ index: Int) -> Widget {
        let item = items[index]
        // Nothing to pin, close, or open a second copy of. The shell's own
        // actions used to hang here for want of anywhere better; they live in
        // the control centre now, which is where a system toggle belongs.
        guard item.key != kLauncherKey else { return SizedBox(width: 0, height: 0) }
        return Positioned(
            left: max(4, tileCentre(index) - 84),
            bottom: Double(kDockHeight) + 6,
            // A fixed width, and .start rather than .stretch: a Positioned
            // child in a Stack is laid out LOOSE, so its width constraint is
            // infinity, and a stretching Column in infinite width lays out to
            // nothing at all — the menu simply never appears, with no error
            // and no clue that layout is what refused it.
            child: SizedBox(width: 168) {
                ClipRRect(borderRadius: BorderRadius.circular(8)) {
                    ColoredBox(color: Color(0xF41F2229)) {
                        Padding(padding: EdgeInsets(left: 0, top: 6, right: 0, bottom: 6)) {
                            Column(mainAxisSize: .min, crossAxisAlignment: .start) {
                                SizedBox(height: 22) {
                                    Padding(padding: EdgeInsets(left: 12, top: 0, right: 12, bottom: 0)) {
                                        Align(alignment: Alignment.centerLeft) {
                                            Text(item.name,
                                                 style: TextStyle(color: Color(0xFF8E96A3),
                                                                  fontSize: 11,
                                                                  fontWeight: .w600),
                                                 overflow: .ellipsis,
                                                 maxLines: 1)
                                        }
                                    }
                                }
                                if item.app != nil {
                                    menuRow(item.isPinned ? "Remove from Dock" : "Keep in Dock") {
                                        self.togglePin(item)
                                    }
                                }
                                if item.isRunning, item.key != kLauncherKey {
                                    menuRow(item.windows.count > 1
                                                ? "Close \(item.windows.count) windows" : "Close") {
                                        self.closeAll(item)
                                    }
                                }
                                if let app = item.app {
                                    menuRow("New window") {
                                        Win32AppCatalog.launch(app)
                                        self.setState { self.menuOpen = nil }
                                    }
                                }
                            }
                        }
                    }
                }
            })
    }

    override func build(_ context: any BuildContext) -> Widget {
        // Rechecked here, where the width is about to be used: a resolution
        // change moves the strip under us and the centring is arithmetic off
        // that width. This build runs once a second anyway, for the clock,
        // so `pointerTile` is never reading a stale screen for long.
        ShellScreen.refresh()
        // The window is the strip PLUS the overhang. The strip is an opaque
        // bar across the bottom; the overhang above it is painted pure black,
        // which the panel's colour key turns into a hole — invisible and
        // click-through until a label or a menu draws there.
        return Directionality(
            textDirection: .ltr,
            child: Listener(
                onPointerDown: { e in
                    let x = e.position.dx, y = e.position.dy
                    // 2 is the secondary button. A press, not a release: the
                    // press is what arrives reliably here, and a menu that
                    // opens on press is what every desktop does anyway.
                    if e.buttons == 2 {
                        let index = self.pointerTile(x, y)
                        self.setState {
                            self.menuOpen = (self.menuOpen == index) ? nil : index
                        }
                        return
                    }
                    if self.controlCentreOpen, self.handleControlCentre(x, y) { return }
                    if self.ccOpener.contains(x, y) {
                        self.setState {
                            self.controlCentreOpen.toggle()
                            self.menuOpen = nil
                        }
                    }
                },
                onPointerMove: { e in
                    // The slider's drag, in one line. A pan recognizer would
                    // be the widget-level answer and is exactly what does not
                    // arrive reliably in this surface.
                    guard self.draggingVolume else { return }
                    self.setState { self.ccSetVolumeFrom(e.position.dx) }
                },
                onPointerUp: { _ in
                    guard self.draggingVolume else { return }
                    self.setState { self.draggingVolume = false }
                },
                onPointerHover: { e in
                    let index = self.pointerTile(e.position.dx, e.position.dy)
                    guard index != self.hovered else { return }
                    self.setState { self.hovered = index }
                },
                child: ColoredBox(color: Color(0x00000000)) {
                Stack(alignment: Alignment.bottomCenter) {
                    // The bar. Positioned rather than Aligned so it spans the
                    // full width whatever it contains — a strip that stops
                    // where its icons stop is the floating slab again.
                    Positioned(left: 0, right: 0, bottom: 0, height: Double(kDockHeight)) {
                        ColoredBox(color: Color(0xF01B1D22)) {
                            Stack(alignment: Alignment.center) {
                                // Centred, Windows 11 style, and centred on
                                // the SCREEN rather than in the space left
                                // over — which is also what makes tileCentre
                                // arithmetic rather than a layout query.
                                Align(alignment: Alignment.center) {
                                    Row(mainAxisSize: .min, crossAxisAlignment: .center) {
                                        for (index, item) in items.enumerated() {
                                            tile(item, index)
                                        }
                                    }
                                }
                                Align(alignment: Alignment.centerRight) {
                                    statusCluster()
                                }
                            }
                        }
                    }
                    // A hairline along the top edge, so the bar reads as
                    // chrome against a window pushed up to it rather than as
                    // part of that window.
                    Positioned(left: 0, right: 0, bottom: Double(kDockHeight), height: 1) {
                        ColoredBox(color: Color(0x24FFFFFF)) { SizedBox(expand: ()) }
                    }
                    // ALWAYS emitted, empty when the panel is down: a Stack
                    // that GAINS a child does not always composite the new one
                    // until something else remounts the subtree, which reads
                    // as a button that did nothing. A constant child count
                    // sidesteps the question.
                    if controlCentreOpen {
                        controlCentre()
                    } else {
                        Positioned(left: 0, bottom: 0) { SizedBox(width: 0, height: 0) }
                    }
                    // A menu wins over a label: the pointer is inside the tile
                    // for both, and two flyouts stacked on one icon is noise.
                    if let open = menuOpen {
                        menu(open)
                    } else if let over = hovered {
                        label(over)
                    }
                }
            }))
    }
}
#endif
