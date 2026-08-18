// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The bar: Starling's menu bar on Windows, and the taskbar inside it.
//
// It lists the windows that exist, says which has focus, raises one on click,
// minimizes the focused one on a second click, closes on middle-click, and
// tiles them all across the work area — every path through
// `Win32WindowManager`, which is what the desktop's own `WindowManager.swift`
// will sit on when it moves across.

#if os(Windows)
// MacosIcon, not Icon: the desktop is macOS-shaped by standing direction
// (see the shell's CLAUDE.md), and the shell's own status bar uses it.
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import Foundation

/// Bar height in LOGICAL POINTS. The host multiplies by the monitor's scale
/// and redoes it on a scale change, so this is 44px on the 100% VM and 88px
/// on a 200% laptop panel with the widget tree seeing 44 either way.
let kBarHeight = 44

/// Width of one window button, and how many fit before the rest collapse into
/// a "+N" tail. Deliberately a constant rather than a measured layout: the
/// bar is one row and the alternative is a scroll view nobody can use with a
/// pointer that has no wheel focus there.
let kButtonWidth = 168.0
let kMaxButtons = 7

/// Gap between tiled windows, in logical points — scaled to pixels at use,
/// because window geometry is the one place this file speaks physical. It is
/// applied on every edge, so adjacent windows are two gaps apart, the same
/// convention the Linux shell's tiler uses.
let kTileGap = 8

final class StarlingBar: StatefulWidget {
    override func createState() -> State<StatefulWidget> { StarlingBarState() }
}

final class StarlingBarState: State<StatefulWidget> {
    private var now = Date()
    private var timer: AnyObject?

    /// The windows, in a STABLE order — see `merge`. `Win32WindowManager`
    /// hands them back in z-order, which is right for Alt+Tab and wrong for a
    /// taskbar: buttons would swap places under the pointer every time focus
    /// moved, so clicking the same window twice would hit two different ones.
    private var windows: [Win32Window] = []
    /// Set while a refresh is already queued: a single new window fires
    /// CREATE, SHOW, FOREGROUND and NAMECHANGE in a burst, and each one would
    /// otherwise walk every top-level window in the session.
    private var refreshQueued = false

    /// Shared with the dock: one texture per app, released when the app's
    /// last window closes.
    private let icons = IconCache()

    override func initState() {
        super.initState()
        // Without this every MacosIcon draws as a tofu box: the icon glyphs
        // live in CupertinoIcons.ttf, which is a SwiftPM resource loaded at
        // runtime, not something the engine's flutter_assets carries.
        CupertinoIcons.registerFont()

        windows = Win32WindowManager.windows()
        syncIcons(windows)

        // Hooks attach to the calling THREAD, so this has to happen here —
        // inside the tree's initState, which runs on the UI thread the
        // message loop owns — and not beside runStarlingApp.
        let watching = Win32WindowManager.observe { [weak self] _ in
            self?.queueRefresh()
        }
        if !watching {
            FileHandle.standardError.write(Data(
                "[WinShellBar] SetWinEventHook refused; the window list will not follow changes\n".utf8))
        }

        // Through hostPeriodicTimerInstall rather than Foundation.Timer: on
        // the DRM embedder a Foundation timer never fires at all (see the
        // desktop's CLAUDE.md), and going through the host keeps every
        // backend honest about which loop the UI thread is really running.
        timer = startPeriodicTimer(seconds: 1.0) { [weak self] in
            guard let self else { return }
            setState { self.now = Date() }
        }
    }

    override func dispose() {
        Win32WindowManager.stopObserving()
        icons.releaseAll()
        super.dispose()
    }

    // MARK: - Icons

    /// Registers a texture for anything new and releases the textures of apps
    /// with no windows left, so an app closing gives its icon back rather
    /// than holding it for the session.
    private func syncIcons(_ windows: [Win32Window]) {
        var live: Set<String> = []
        for window in windows {
            live.insert(IconCache.key(for: window))
            icons.ensure(window: window, size: 32)
        }
        icons.retain(only: live)
    }

    // MARK: - The window list

    private func queueRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        // The Win32 host drains the GCD main queue from its message loop, so
        // this lands back on this same thread once the current burst of
        // events has been dispatched.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            refreshQueued = false
            let fresh = Win32WindowManager.windows()
            syncIcons(fresh)
            setState { self.windows = self.merge(fresh) }
        }
    }

    /// Keeps a window where it already was and appends the newcomers, so a
    /// button never moves out from under the pointer. Windows that went away
    /// simply fall out — they are absent from `fresh`.
    private func merge(_ fresh: [Win32Window]) -> [Win32Window] {
        var byHandle: [UInt64: Win32Window] = [:]
        for w in fresh { byHandle[w.handle] = w }

        var ordered: [Win32Window] = []
        ordered.reserveCapacity(fresh.count)
        var placed = Set<UInt64>()
        for old in windows {
            if let still = byHandle[old.handle] {
                ordered.append(still)
                placed.insert(old.handle)
            }
        }
        for w in fresh where !placed.contains(w.handle) {
            ordered.append(w)
        }
        return ordered
    }

    // MARK: - Actions

    /// Lays every non-minimized window out in a grid — one grid PER MONITOR,
    /// over that monitor's work area.
    ///
    /// Grouping by the monitor a window is already on matters as soon as
    /// there are two: tiling everything into the primary would drag every
    /// window off the second screen, which is what "tile" means on a
    /// one-monitor desktop and never what it means on two.
    ///
    /// The work area, not the monitor rectangle: it is already the screen
    /// minus explorer's taskbar and minus our own appbar strip, so the tiling
    /// lands under the bar without this code knowing the bar exists.
    private func tileAll() {
        let visible = windows.filter { !$0.isMinimized }
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

    // MARK: - Build

    private func clockText() -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm  EEE d MMM"
        return f.string(from: now)
    }

    /// The fallback glyph, for an app whose own icon would not resolve —
    /// chosen from the executable name rather than the title, because Windows
    /// has no `app_id` and a title is a document (the desktop's own notes
    /// make the same point about `untitled – Main.java`).
    private func glyph(for window: Win32Window) -> IconData {
        switch window.appName.lowercased() {
        case "chrome", "msedge", "firefox", "brave": return CupertinoIcons.globe
        case "explorer": return CupertinoIcons.folder
        case "code", "devenv", "notepad", "idea64": return CupertinoIcons.doc_text
        case "windowsterminal", "cmd", "powershell", "pwsh", "conhost":
            return CupertinoIcons.chevron_left_slash_chevron_right
        default: return CupertinoIcons.app_badge
        }
    }

    private func windowButton(_ window: Win32Window) -> Widget {
        // ColoredBox inside ClipRRect rather than a BoxDecoration: the fill
        // is flat and the only thing wanted from the decoration would be the
        // radius, which the clip already gives.
        let fill = window.isForeground ? Color(0x33FFFFFF)
            : window.isMinimized ? Color(0x0AFFFFFF) : Color(0x18FFFFFF)
        let ink = window.isMinimized ? Color(0xFF8E96A3) : Color(0xFFE6EAF0)

        return GestureDetector(
            // Clicking the focused window's own button minimizes it, the way
            // every taskbar since Windows 95 has behaved.
            onTap: {
                if window.isForeground {
                    Win32WindowManager.minimize(window.handle)
                } else {
                    Win32WindowManager.activate(window.handle)
                }
                self.queueRefresh()
            },
            // Middle-click closes. Secondary (right) would want a MacosMenu,
            // which is the next thing this bar grows.
            onTertiaryTapUp: { _ in
                Win32WindowManager.close(window.handle)
                self.queueRefresh()
            },
            child: Padding(padding: EdgeInsets(left: 0, top: 0, right: 6, bottom: 0)) {
                ClipRRect(borderRadius: BorderRadius.circular(6)) {
                    ColoredBox(color: fill) {
                        SizedBox(width: kButtonWidth, height: 30) {
                            Padding(padding: EdgeInsets(left: 9, top: 0, right: 9, bottom: 0)) {
                                Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 7) {
                                    // Drawn at full strength even when the
                                    // window is minimized. An Opacity of 0.45
                                    // over this made the icon vanish outright
                                    // rather than dim — anything below 1.0
                                    // pushes the tree through a saveLayer, and
                                    // an external texture does not survive one
                                    // on this embedder. The dimmed label and
                                    // the darker fill carry the state instead.
                                    if let icon = icons.view(IconCache.key(for: window), side: 16) {
                                        icon
                                    } else {
                                        MacosIcon(icon: glyph(for: window), color: ink, size: 13)
                                    }
                                    Expanded {
                                        Text(window.title,
                                             style: TextStyle(color: ink, fontSize: 12),
                                             overflow: .ellipsis,
                                             maxLines: 1)
                                    }
                                }
                            }
                        }
                    }
                }
            })
    }

    private func barButton(_ icon: IconData, _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: action,
            child: Padding(padding: EdgeInsets(left: 2, top: 0, right: 2, bottom: 0)) {
                ClipRRect(borderRadius: BorderRadius.circular(6)) {
                    ColoredBox(color: Color(0x18FFFFFF)) {
                        SizedBox(width: 30, height: 30) {
                            Center {
                                MacosIcon(icon: icon, color: Color(0xFFD5DAE3), size: 15)
                            }
                        }
                    }
                }
            })
    }

    override func build(_ context: any BuildContext) -> Widget {
        let shown = Array(windows.prefix(kMaxButtons))
        let hidden = windows.count - shown.count

        // The desktop's own menu-bar palette: near-black with a hairline
        // under it, so it reads as chrome against any wallpaper.
        // Directionality is an inherited widget and has no trailing-closure
        // overload — the ported `child:` spelling is the only one for it.
        return Directionality(
            textDirection: .ltr,
            child: ColoredBox(color: Color(0xF01B1D22)) {
                Padding(padding: EdgeInsets(left: 14, top: 0, right: 14, bottom: 0)) {
                    Row(crossAxisAlignment: .center) {
                        // The Starling button opens the launcher, which is
                        // a different PROCESS — one widget root per process —
                        // so the click becomes a broadcast rather than a call.
                        GestureDetector(
                            onTap: { Win32Shell.toggleOverlay() },
                            child: Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 8) {
                                MacosIcon(icon: CupertinoIcons.sparkles, color: Color(0xFF7FB0FF), size: 16)
                                Text("Starling",
                                     style: TextStyle(color: Color(0xFFFFFFFF),
                                                      fontSize: 13,
                                                      fontWeight: .w600))
                            })
                        Expanded {
                            Padding(padding: EdgeInsets(left: 18, top: 0, right: 18, bottom: 0)) {
                                Row(mainAxisSize: .min, crossAxisAlignment: .center) {
                                    for window in shown { windowButton(window) }
                                    if hidden > 0 {
                                        Text("+\(hidden)",
                                             style: TextStyle(color: Color(0xFF8E96A3), fontSize: 12))
                                    }
                                }
                            }
                        }
                        Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 4) {
                            barButton(CupertinoIcons.square_grid_2x2) { self.tileAll() }
                            MacosIcon(icon: CupertinoIcons.wifi, color: Color(0xFFD5DAE3), size: 15)
                            MacosIcon(icon: CupertinoIcons.battery_full, color: Color(0xFFD5DAE3), size: 17)
                            Padding(padding: EdgeInsets(left: 6, top: 0, right: 0, bottom: 0)) {
                                Text(clockText(),
                                     style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 13))
                            }
                        }
                    }
                }
            })
    }
}
#endif
