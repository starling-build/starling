// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The dock, on Windows.
//
// This is the piece that makes the port read as STARLING rather than as
// another Windows taskbar replacement: a macOS-shaped dock along the bottom
// edge, showing the apps you keep plus the apps you are running, with a
// running-indicator under each. Clicking one raises it, or starts it.
//
// Where the apps come from is the interesting part. The Linux shell reads
// Starling's own registry; Windows has none, so `Win32AppCatalog` reads the
// START MENU — the same tree Explorer's Start reads — and that is the
// catalog behind both this and anything else that needs "what is installed".

#if os(Windows)
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import Foundation

/// Dock height in logical points, and the icon size inside it.
let kDockHeight = 78
let kDockIcon = 44.0

/// What the dock keeps even when nothing of that app is running. Matched
/// loosely against the Start Menu name, because the exact wording moves
/// between Windows releases ("Command Prompt" vs "Terminal") and a dock that
/// silently loses an entry after an update is worse than one that keeps a
/// near match.
let kPinned = ["file explorer", "terminal", "notepad", "paint", "edge", "settings"]

/// One dock entry: an installed app, a running app, or both.
struct DockItem {
    let key: String
    let name: String
    /// nil for something running that we could not find in the Start Menu —
    /// it still shows and still raises, it just cannot be launched again.
    let app: Win32App?
    /// Every window this app has, most recently used first.
    let windows: [Win32Window]
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

    override func initState() {
        super.initState()
        CupertinoIcons.registerFont()
        catalog = Win32AppCatalog.apps()
        print("[WinShellDock] \(catalog.count) apps in the Start Menu")
        rebuild()
        Win32WindowManager.observe { [weak self] _ in self?.queueRefresh() }
    }

    override func dispose() {
        Win32WindowManager.stopObserving()
        icons.releaseAll()
        super.dispose()
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

    /// Pinned apps first, in the order `kPinned` names them, then whatever
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

        for wanted in kPinned {
            guard let app = catalog.first(where: {
                $0.name.lowercased().contains(wanted)
            }) else { continue }
            let key = IconCache.key(for: app)
            guard !claimed.contains(key) else { continue }
            claimed.insert(key)
            built.append(DockItem(key: key, name: app.name, app: app,
                                  windows: byExe[key] ?? []))
        }

        for window in windows {
            let key = IconCache.key(for: window)
            guard !claimed.contains(key) else { continue }
            claimed.insert(key)
            let app = catalog.first(where: { IconCache.key(for: $0) == key })
            built.append(DockItem(key: key, name: app?.name ?? window.appName,
                                  app: app, windows: byExe[key] ?? []))
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
        items = built
    }

    // MARK: - Actions

    /// The dock's whole interaction model, in one place. Not running: start
    /// it. Running but not focused: raise it. Focused: put it away — which is
    /// what a dock icon does everywhere else and is the reason a dock is
    /// faster than Alt+Tab for the app you keep coming back to.
    private func activate(_ item: DockItem) {
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

    // MARK: - Build

    private func tile(_ item: DockItem) -> Widget {
        GestureDetector(
            onTap: { self.activate(item) },
            child: Padding(padding: EdgeInsets(left: 5, top: 0, right: 5, bottom: 0)) {
                Column(mainAxisSize: .min, crossAxisAlignment: .center) {
                    if let icon = icons.view(item.key, side: kDockIcon) {
                        icon
                    } else {
                        SizedBox(width: kDockIcon, height: kDockIcon) {
                            Center {
                                MacosIcon(icon: CupertinoIcons.app_badge,
                                          color: Color(0xFFB8C0CC), size: 26)
                            }
                        }
                    }
                    // The running indicator: present for a running app,
                    // brighter for the focused one. A dot rather than a
                    // highlight behind the icon, so the app's own artwork
                    // stays the thing the eye lands on.
                    SizedBox(height: 7) {
                        Center {
                            ClipRRect(borderRadius: BorderRadius.circular(2.5)) {
                                ColoredBox(color: item.isForeground ? Color(0xFFFFFFFF)
                                    : item.isRunning ? Color(0x99FFFFFF)
                                    : Color(0x00000000)) {
                                    SizedBox(width: 5, height: 5)
                                }
                            }
                        }
                    }
                }
            })
    }

    override func build(_ context: any BuildContext) -> Widget {
        // A translucent slab floating over the wallpaper rather than a bar
        // welded to the screen edge — the shape the desktop uses on Linux.
        // The window behind it is the full strip; the visible dock is this
        // rounded box inside it, which is why the panel reserves 78pt and the
        // slab is shorter.
        return Directionality(
            textDirection: .ltr,
            child: ColoredBox(color: Color(0x00000000)) {
                Center {
                    ClipRRect(borderRadius: BorderRadius.circular(16)) {
                        ColoredBox(color: Color(0xE01B1D22)) {
                            Padding(padding: EdgeInsets(left: 10, top: 7, right: 10, bottom: 5)) {
                                Row(mainAxisSize: .min, crossAxisAlignment: .center) {
                                    for item in items { tile(item) }
                                }
                            }
                        }
                    }
                }
            })
    }
}
#endif
