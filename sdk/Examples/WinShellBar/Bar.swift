// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The bar: Starling's menu bar on Windows, and the taskbar inside it.
//
// It lists the apps that are running, says which has focus, raises one on
// click, cycles a multi-window app, minimizes on a second click, closes on
// middle-click, and tiles everything across the work area — every path
// through `Win32WindowManager`, which is what the desktop's own
// `WindowManager.swift` will sit on when it moves across.
//
// The right-hand cluster is read from the system (`Win32Status`), not drawn:
// a bar with a fixed wifi glyph and a fixed battery glyph is a picture of a
// status bar.

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

/// Width of one taskbar button, and how many fit before the rest collapse
/// into a "+N" tail.
let kButtonWidth = 176.0
let kMaxButtons = 7

/// Gap between tiled windows, in logical points — scaled to pixels at use,
/// because window geometry is the one place this file speaks physical. It is
/// applied on every edge, so adjacent windows are two gaps apart, the same
/// convention the Linux shell's tiler uses.
let kTileGap = 8

/// One taskbar entry: an app, with every window it has.
///
/// Per APP, not per window. A taskbar with one button per window fills up
/// with four identical "Untitled - Notepad" entries and makes the user read
/// titles to find the thing they want; every real taskbar groups, and so does
/// the Starling dock, so the two now agree about what an entry means.
struct TaskGroup {
    let key: String
    let name: String
    let windows: [Win32Window]

    var isForeground: Bool { windows.contains { $0.isForeground } }
    /// Only counts as minimized when ALL of them are — an app with one window
    /// minimized and another on screen is not away.
    var isMinimized: Bool { windows.allSatisfy { $0.isMinimized } }

    /// What the button says: the window's own title when there is one window,
    /// the app plus a count when there are more. A title is a document, and
    /// four documents want the app's name above them.
    var label: String {
        if windows.count == 1 { return windows[0].title }
        return "\(name)  ·  \(windows.count)"
    }
}

final class StarlingBar: StatefulWidget {
    override func createState() -> State<StatefulWidget> { StarlingBarState() }
}

final class StarlingBarState: State<StatefulWidget> {
    private var now = Date()
    private var timer: AnyObject?

    /// Shared with the dock: one texture per app, released when the app's
    /// last window closes.
    private let icons = IconCache()

    private var groups: [TaskGroup] = []
    /// The order groups appear in, kept across refreshes. `windows()` returns
    /// z-order, which is right for Alt+Tab and wrong for a taskbar: buttons
    /// would swap places under the pointer every time focus moved, so
    /// clicking the same app twice would hit two different ones.
    private var groupOrder: [String] = []
    private var refreshQueued = false

    // The status cluster, re-read on the same tick as the clock.
    private var network = Win32Network(kind: .none, signal: 0, ssid: "")
    private var power = Win32Power(hasBattery: false, percent: nil, isCharging: true)
    private var volume: Win32Volume?

    override func initState() {
        super.initState()
        // Without this every MacosIcon draws as a tofu box: the icon glyphs
        // live in CupertinoIcons.ttf, which is a SwiftPM resource loaded at
        // runtime, not something the engine's flutter_assets carries.
        CupertinoIcons.registerFont()

        rebuild(Win32WindowManager.windows())
        readStatus()

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

    // MARK: - Status

    /// Polled, not subscribed. Each of the three has its own notification
    /// mechanism, they deliver on three different threads, and a status bar
    /// that updates a second late is indistinguishable from one that does not.
    private func readStatus() {
        network = Win32Status.network()
        power = Win32Status.power()
        volume = Win32Status.volume()
    }

    // MARK: - The task list

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
            setState { self.rebuild(fresh) }
        }
    }

    private func rebuild(_ windows: [Win32Window]) {
        var byApp: [String: [Win32Window]] = [:]
        var names: [String: String] = [:]
        var live: Set<String> = []
        for window in windows {
            let key = IconCache.key(for: window)
            byApp[key, default: []].append(window)
            if names[key] == nil { names[key] = window.appName }
            live.insert(key)
            icons.ensure(window: window, size: 32)
        }
        icons.retain(only: live)

        // Keep known apps where they were, append the newcomers, drop the
        // ones that closed.
        groupOrder = groupOrder.filter { live.contains($0) }
        for key in windows.map({ IconCache.key(for: $0) }) where !groupOrder.contains(key) {
            groupOrder.append(key)
        }
        groups = groupOrder.compactMap { key in
            guard let windows = byApp[key] else { return nil }
            return TaskGroup(key: key, name: names[key] ?? "", windows: windows)
        }
    }

    // MARK: - Actions

    /// A taskbar button's whole behaviour. Not focused: raise it. Focused with
    /// one window: put it away. Focused with several: move to the next one,
    /// which is how a grouped button stays useful instead of being a toggle
    /// you have to click twice to get past.
    private func activate(_ group: TaskGroup) {
        if let focused = group.windows.first(where: { $0.isForeground }) {
            if group.windows.count == 1 {
                Win32WindowManager.minimize(focused.handle)
            } else {
                let index = group.windows.firstIndex(where: { $0.handle == focused.handle }) ?? 0
                let next = group.windows[(index + 1) % group.windows.count]
                Win32WindowManager.activate(next.handle)
            }
        } else {
            let target = group.windows.first(where: { !$0.isMinimized }) ?? group.windows[0]
            Win32WindowManager.activate(target.handle)
        }
        queueRefresh()
    }

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
        let visible = groups.flatMap { $0.windows }.filter { !$0.isMinimized }
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
    private func glyph(for name: String) -> IconData {
        switch name.lowercased() {
        case "chrome", "msedge", "firefox", "brave": return CupertinoIcons.globe
        case "explorer": return CupertinoIcons.folder
        case "code", "devenv", "notepad", "idea64": return CupertinoIcons.doc_text
        case "windowsterminal", "cmd", "powershell", "pwsh", "conhost":
            return CupertinoIcons.chevron_left_slash_chevron_right
        default: return CupertinoIcons.app_badge
        }
    }

    private func taskButton(_ group: TaskGroup) -> Widget {
        // ColoredBox inside ClipRRect rather than a BoxDecoration: the fill
        // is flat and the only thing wanted from the decoration would be the
        // radius, which the clip already gives.
        let fill = group.isForeground ? Color(0x33FFFFFF)
            : group.isMinimized ? Color(0x0AFFFFFF) : Color(0x18FFFFFF)
        let ink = group.isMinimized ? Color(0xFF8E96A3) : Color(0xFFE6EAF0)

        return GestureDetector(
            onTap: { self.activate(group) },
            // Middle-click closes the frontmost window of the app, not the
            // app: closing four documents on one click is not something to
            // do by accident. Secondary (right) would want a MacosMenu, which
            // is the next thing this bar grows.
            onTertiaryTapUp: { _ in
                let target = group.windows.first(where: { $0.isForeground })
                    ?? group.windows[0]
                Win32WindowManager.close(target.handle)
                self.queueRefresh()
            },
            child: Padding(padding: EdgeInsets(left: 0, top: 0, right: 6, bottom: 0)) {
                ClipRRect(borderRadius: BorderRadius.circular(6)) {
                    ColoredBox(color: fill) {
                        SizedBox(width: kButtonWidth, height: 30) {
                            Padding(padding: EdgeInsets(left: 9, top: 0, right: 9, bottom: 0)) {
                                Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 7) {
                                    // Drawn at full strength even when the app
                                    // is minimized. An Opacity of 0.45 over
                                    // this made the icon vanish outright
                                    // rather than dim — anything below 1.0
                                    // pushes the tree through a saveLayer, and
                                    // an external texture does not survive one
                                    // on this embedder. The dimmed label and
                                    // the darker fill carry the state instead.
                                    if let icon = icons.view(group.key, side: 16) {
                                        icon
                                    } else {
                                        MacosIcon(icon: glyph(for: group.name), color: ink, size: 13)
                                    }
                                    Expanded {
                                        Text(group.label,
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

    // MARK: - The status cluster

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

    override func build(_ context: any BuildContext) -> Widget {
        let shown = Array(groups.prefix(kMaxButtons))
        let hidden = groups.count - shown.count

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
                                    for group in shown { taskButton(group) }
                                    if hidden > 0 {
                                        Text("+\(hidden)",
                                             style: TextStyle(color: Color(0xFF8E96A3), fontSize: 12))
                                    }
                                }
                            }
                        }
                        Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 8) {
                            barButton(CupertinoIcons.square_grid_2x2) { self.tileAll() }
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
            })
    }
}
#endif
