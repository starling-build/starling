// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The dock, on Windows.
//
// This is the piece that makes the port read as STARLING rather than as
// another Windows taskbar replacement: a macOS-shaped dock along the bottom
// edge, showing the apps you keep plus the apps you are running, with a
// running indicator under each. Clicking one raises it, or starts it;
// right-clicking pins or unpins it; hovering names it.
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

/// Dock height in logical points, and the icon size inside it.
let kDockHeight = 78
let kDockIcon = 44.0

/// How far the dock's WINDOW extends above the strip it reserves. The label
/// and the menu draw in here; a window is a hard clip, so without it they
/// would be cut off at the top of the strip. It reserves nothing and is
/// transparent, so it is invisible and click-through until something paints.
let kDockOverhang = 190

/// Geometry the flyout arithmetic needs. The tile is a fixed size, so where
/// each one sits is arithmetic rather than a layout query — which is what
/// lets a label be positioned over an icon without measuring anything.
let kDockTile = kDockIcon + 10.0
let kDockPadding = 10.0

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

    override func initState() {
        super.initState()
        CupertinoIcons.registerFont()
        catalog = Win32AppCatalog.apps()
        pins = loadPins()
        print("[WinShellDock] \(catalog.count) apps in the Start Menu, \(pins.count) pinned")
        rebuild()
        Win32WindowManager.observe { [weak self] _ in self?.queueRefresh() }
    }

    override func dispose() {
        Win32WindowManager.stopObserving()
        icons.releaseAll()
        super.dispose()
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

    // MARK: - Geometry

    /// Which tile a point in the panel is over, or nil.
    ///
    /// Hit-tested by ARITHMETIC, from a Listener at the root, because the two
    /// widget-level routes both come up empty on this framework:
    /// `MouseRegion.onEnter`/`onExit` never fire, and `onSecondaryTap` never
    /// fires either — even though the raw events are demonstrably arriving
    /// (a root Listener sees `hover` and sees `down buttons=2`). Recognizers
    /// and mouse-tracker annotations are the missing link, not the host. The
    /// tile is a fixed size and the slab is centred, so doing it here costs
    /// four lines and no layout query.
    private func pointerTile(_ x: Double, _ y: Double) -> Int? {
        guard !items.isEmpty else { return nil }
        let height = Double(kDockHeight + kDockOverhang)
        // The slab sits at the bottom, 8pt clear of the edge.
        let slabBottom = height - 8
        let slabTop = slabBottom - (kDockIcon + 19)
        guard y >= slabTop, y <= slabBottom else { return nil }

        let width = Double(Win32Display.primary()?.logicalWidth ?? 1280)
        let slab = Double(items.count) * kDockTile + kDockPadding * 2
        let left = (width - slab) / 2 + kDockPadding
        let index = Int((x - left) / kDockTile)
        guard x >= left, index >= 0, index < items.count else { return nil }
        return index
    }

    /// Where a tile's centre sits, in the panel's own coordinates. The tile is
    /// a fixed size and the slab is centred, so this is arithmetic — no
    /// measuring, which is what lets a flyout be positioned over an icon
    /// without a layout pass to ask where it ended up.
    private func tileCentre(_ index: Int) -> Double {
        let width = Double(Win32Display.primary()?.logicalWidth ?? 1280)
        let slab = Double(items.count) * kDockTile + kDockPadding * 2
        return (width - slab) / 2 + kDockPadding + Double(index) * kDockTile + kDockTile / 2
    }

    // MARK: - Build

    private func tile(_ item: DockItem, _ index: Int) -> Widget {
        // Only the primary tap lives on the tile. Hover and the right-click
        // menu are driven from a Listener at the root instead — see the note
        // on `pointerTile`.
        GestureDetector(
                onTap: { self.activate(item) },
                child: Padding(padding: EdgeInsets(left: 5, top: 0, right: 5, bottom: 0)) {
                    Column(mainAxisSize: .min, crossAxisAlignment: .center) {
                        if item.key == kLauncherKey {
                            SizedBox(width: kDockIcon, height: kDockIcon) {
                                ClipRRect(borderRadius: BorderRadius.circular(10)) {
                                    ColoredBox(color: Color(0xFF2B3550)) {
                                        Center {
                                            MacosIcon(icon: CupertinoIcons.square_grid_2x2,
                                                      color: Color(0xFF9EC2FF), size: 26)
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
                                              color: Color(0xFFB8C0CC), size: 26)
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

    /// The hover label. Drawn in the overhang, above the slab.
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
        // Nothing to pin, close, or launch a second copy of.
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
                                if item.isRunning {
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
        // The window is the strip PLUS the overhang; the slab lives at the
        // bottom of it and the flyouts draw above. Everything the tree paints
        // as pure black is a hole (the panel's colour key), which is what
        // makes the overhang invisible and click-through.
        return Directionality(
            textDirection: .ltr,
            child: Listener(
                onPointerDown: { e in
                    // 2 is the secondary button. A press, not a release: the
                    // press is what arrives reliably here, and a menu that
                    // opens on press is what every desktop does anyway.
                    guard e.buttons == 2 else { return }
                    let index = self.pointerTile(e.position.dx, e.position.dy)
                    self.setState {
                        self.menuOpen = (self.menuOpen == index) ? nil : index
                    }
                },
                onPointerHover: { e in
                    let index = self.pointerTile(e.position.dx, e.position.dy)
                    guard index != self.hovered else { return }
                    self.setState { self.hovered = index }
                },
                child: ColoredBox(color: Color(0x00000000)) {
                Stack(alignment: Alignment.bottomCenter) {
                    Align(alignment: Alignment.bottomCenter) {
                        Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8)) {
                            ClipRRect(borderRadius: BorderRadius.circular(16)) {
                                ColoredBox(color: Color(0xE01B1D22)) {
                                    Padding(padding: EdgeInsets(left: kDockPadding, top: 7,
                                                               right: kDockPadding, bottom: 5)) {
                                        Row(mainAxisSize: .min, crossAxisAlignment: .center) {
                                            for (index, item) in items.enumerated() {
                                                tile(item, index)
                                            }
                                        }
                                    }
                                }
                            }
                        }
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
