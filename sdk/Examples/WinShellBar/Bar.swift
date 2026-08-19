// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The bar: Starling's MENU bar on Windows.
//
// It was a taskbar first — a row of window buttons, because the bar existed
// before the dock did. Once the dock landed that was two of the same thing on
// one screen, and on the wrong edge: this desktop is macOS-shaped, and there
// the running apps live in the dock at the bottom while the top strip belongs
// to the focused app. So the window list moved out and this became what a
// menu bar is: the Starling menu, the focused app's name, its windows, and
// the status cluster.
//
// Windows has no way to ask another process for its menus (a Win32 menu bar
// belongs to the app's own window, and a ribbon is not a menu at all), so the
// app menu here is not the app's — it is the window commands we can honestly
// perform through `Win32WindowManager`. That is the same shape the rest of
// this port takes: we never own their pixels, we own their geometry.
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

/// Points the bar's WINDOW extends below the strip it reserves, so a menu has
/// somewhere to draw. Same trick as the dock's overhang and for the same
/// reason — a window is a hard clip — and it is why the bar is a transparent
/// panel now: everything the tree paints as pure black is a hole.
let kBarOverhang = 340

/// Width of a menu flyout. Fixed, because the flyout hangs off a Positioned
/// and a loose child has no width to stretch into.
let kMenuWidth = 210.0

/// Which of the bar's menus is open.
enum BarMenu: Equatable {
    case starling
    case app
    case window
}

/// A menu title, and where it sits.
///
/// The width is COMPUTED rather than measured, and then imposed on the title
/// with a SizedBox — so the estimate cannot drift from the layout, and the
/// flyout below can be positioned by arithmetic with no layout query. Exactly
/// the trick the dock uses for its tiles.
struct BarTitle {
    let kind: BarMenu
    let label: String
    let bold: Bool
    let x: Double
    let width: Double
}

/// Whether Explorer's taskbar is left alone. main.swift decides it once at
/// startup; the bar re-reads it because the re-assert below lives here, on
/// the tick that is already running.
private let keepsNativeTaskbar =
    CommandLine.arguments.contains("--keep-taskbar")
    || CommandLine.arguments.contains("--plain")

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

    private var groups: [TaskGroup] = []
    /// The order groups appear in, kept across refreshes. `windows()` returns
    /// z-order, which is right for Alt+Tab and wrong for a taskbar: buttons
    /// would swap places under the pointer every time focus moved, so
    /// clicking the same app twice would hit two different ones.
    private var groupOrder: [String] = []
    private var refreshQueued = false

    /// Which menu is down, and the window that had focus when it opened.
    ///
    /// The second is the dismiss. A panel is WS_EX_NOACTIVATE, so opening a
    /// menu does not move the foreground and we never get a kill-focus to
    /// close on; and the overhang is colour-keyed, so a click out there goes
    /// to whatever is underneath and we never see it either. What we DO see
    /// is the foreground changing — which is precisely what "the user clicked
    /// somewhere else" looks like from here.
    private var menuOpen: BarMenu?
    private var menuForeground: UInt64 = 0
    /// The Starling menu's taskbar toggle: while this is set the one-second
    /// re-assert stands down, so "Show Windows Taskbar" stays shown.
    private var nativeTaskbarWanted = false

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
        print("[WinShellBar] \(groups.count) apps, front=\(frontGroup?.name ?? "none")")

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
            // Explorer puts its taskbar back on its own — a display change, a
            // Settings round-trip, or explorer restarting after a crash all
            // do it, and none of them tell us. Re-asserting here costs two
            // FindWindowEx calls a second and is the difference between a
            // takeover that holds and one that lasts until the first
            // resolution change.
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
        }

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

        // Close an open menu when the foreground moves — see `menuForeground`.
        if menuOpen != nil, frontHandle() != menuForeground { menuOpen = nil }
    }

    private var frontGroup: TaskGroup? { groups.first(where: { $0.isForeground }) }

    private func frontHandle() -> UInt64 {
        frontGroup?.windows.first(where: { $0.isForeground })?.handle ?? 0
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

    // MARK: - Titles and menus

    /// The titles, left to right, with the geometry their flyouts hang from.
    ///
    /// Widths are COMPUTED and then imposed with a SizedBox, so a bad estimate
    /// can only ellipsize a title — never misplace the menu under it. Measuring
    /// would need a layout pass to read back, and the flyout has to be built in
    /// the same frame as the title.
    private func titles() -> [BarTitle] {
        var out: [BarTitle] = []
        var x = 14.0
        func add(_ kind: BarMenu, _ label: String, bold: Bool, icon: Bool = false) {
            let width = min(230.0, 24 + (icon ? 22.0 : 0) + Double(label.count) * 8.0)
            out.append(BarTitle(kind: kind, label: label, bold: bold, x: x, width: width))
            x += width + 2
        }
        add(.starling, "Starling", bold: true, icon: true)
        if let front = frontGroup {
            add(.app, front.name, bold: true)
            // Only when there is a choice to make. A Window menu listing one
            // window is a menu that does nothing.
            if front.windows.count > 1 { add(.window, "Window", bold: false) }
        }
        return out
    }

    private func titleChip(_ title: BarTitle) -> Widget {
        let active = menuOpen == title.kind
        return GestureDetector(
            onTap: {
                self.setState {
                    self.menuOpen = active ? nil : title.kind
                    self.menuForeground = self.frontHandle()
                }
            },
            child: Padding(padding: EdgeInsets(left: 0, top: 0, right: 2, bottom: 0)) {
                ClipRRect(borderRadius: BorderRadius.circular(6)) {
                    // Transparent WHITE, not black: this panel is colour-keyed,
                    // so a pure-black fill here would punch a hole through the
                    // bar rather than show the bar behind it.
                    ColoredBox(color: active ? Color(0x33FFFFFF) : Color(0x00FFFFFF)) {
                        SizedBox(width: title.width, height: 28) {
                            Padding(padding: EdgeInsets(left: 9, top: 0, right: 9, bottom: 0)) {
                                Row(crossAxisAlignment: .center, spacing: 7) {
                                    if title.kind == .starling {
                                        MacosIcon(icon: CupertinoIcons.sparkles,
                                                  color: Color(0xFF7FB0FF), size: 16)
                                    }
                                    Expanded {
                                        Text(title.label,
                                             style: TextStyle(color: Color(0xFFFFFFFF),
                                                              fontSize: 13,
                                                              fontWeight: title.bold ? .w600 : .w400),
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

    private func menuRow(_ text: String, _ action: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: {
                action()
                self.setState { self.menuOpen = nil }
            },
            child: SizedBox(width: kMenuWidth, height: 28) {
                Padding(padding: EdgeInsets(left: 12, top: 0, right: 12, bottom: 0)) {
                    Align(alignment: Alignment.centerLeft) {
                        Text(text,
                             style: TextStyle(color: Color(0xFFE6EAF0), fontSize: 12),
                             overflow: .ellipsis,
                             maxLines: 1)
                    }
                }
            })
    }

    private func menuSeparator() -> Widget {
        Padding(padding: EdgeInsets(left: 12, top: 5, right: 12, bottom: 5)) {
            SizedBox(width: kMenuWidth - 24, height: 1) {
                ColoredBox(color: Color(0x22FFFFFF)) { SizedBox(expand: ()) }
            }
        }
    }

    private func starlingMenu() -> [Widget] {
        [
            menuRow("Launcher") { Win32Shell.toggleOverlay() },
            menuRow("Tile Windows") { self.tileAll() },
            menuSeparator(),
            // The escape hatch, in the place a user would look for it. The
            // one-second re-assert stands down while this is set, or the
            // taskbar would come back for a second and vanish again.
            menuRow(nativeTaskbarWanted ? "Hide Windows Taskbar" : "Show Windows Taskbar") {
                self.nativeTaskbarWanted.toggle()
                if self.nativeTaskbarWanted {
                    Win32Shell.showNativeTaskbar()
                } else {
                    Win32Shell.hideNativeTaskbar()
                }
            },
        ]
    }

    /// Not the app's own menus — Windows has no way to hand those over. These
    /// are the window commands this shell can actually carry out.
    private func appMenu(_ front: TaskGroup) -> [Widget] {
        let target = front.windows.first(where: { $0.isForeground }) ?? front.windows[0]
        var rows: [Widget] = [
            menuRow("Minimize") {
                _ = Win32WindowManager.minimize(target.handle)
                self.queueRefresh()
            }
        ]
        if front.windows.count > 1 {
            rows.append(menuRow("Next Window") { self.activate(front) })
        }
        rows.append(menuSeparator())
        rows.append(menuRow("Close Window") {
            _ = Win32WindowManager.close(target.handle)
            self.queueRefresh()
        })
        if front.windows.count > 1 {
            rows.append(menuRow("Close All \(front.windows.count) Windows") {
                for window in front.windows { _ = Win32WindowManager.close(window.handle) }
                self.queueRefresh()
            })
        }
        return rows
    }

    private func windowMenu(_ front: TaskGroup) -> [Widget] {
        front.windows.map { window in
            // A bullet for the one in front. Not a checkmark glyph: the menu
            // rows are plain Text and a leading dot keeps them aligned.
            menuRow((window.isForeground ? "•  " : "    ") + window.title) {
                _ = Win32WindowManager.activate(window.handle)
                self.queueRefresh()
            }
        }
    }

    /// Where the open menu hangs, and what is in it — both nil-safe, because
    /// the slot in the Stack is always there. See the note in `build`.
    private func menuAnchor(_ titles: [BarTitle]) -> Double {
        guard let open = menuOpen,
              let title = titles.first(where: { $0.kind == open }) else { return 0 }
        return title.x
    }

    private func openMenu(_ titles: [BarTitle]) -> Widget {
        guard let open = menuOpen,
              titles.contains(where: { $0.kind == open }) else {
            return SizedBox(width: 0, height: 0)
        }
        return menuPanel(open)
    }

    private func menuPanel(_ kind: BarMenu) -> Widget {
        // Fixed width and .start rather than .stretch: this hangs off a
        // Positioned, which is laid out LOOSE, and a stretching Column in an
        // infinite width lays out to nothing at all — the menu just never
        // appears, with no error to say layout refused it.
        SizedBox(width: kMenuWidth) {
            ClipRRect(borderRadius: BorderRadius.circular(8)) {
                ColoredBox(color: Color(0xF41F2229)) {
                    Padding(padding: EdgeInsets(left: 0, top: 6, right: 0, bottom: 6)) {
                        Column(mainAxisSize: .min, crossAxisAlignment: .start) {
                            switch kind {
                            case .starling:
                                for row in starlingMenu() { row }
                            case .app:
                                if let front = frontGroup {
                                    for row in appMenu(front) { row }
                                }
                            case .window:
                                if let front = frontGroup {
                                    for row in windowMenu(front) { row }
                                }
                            }
                        }
                    }
                }
            }
        }
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
        let titles = self.titles()

        // The window is the strip PLUS the overhang, and everything painted
        // pure black in it is a hole (the panel's colour key) — which is what
        // lets the menu draw below the bar without a black slab hanging off
        // the top of the screen when no menu is open.
        //
        // Directionality is an inherited widget and has no trailing-closure
        // overload — the ported `child:` spelling is the only one for it.
        return Directionality(
            textDirection: .ltr,
            child: ColoredBox(color: Color(0x00000000)) {
                Stack(alignment: Alignment.topLeft) {
                    Positioned(left: 0, top: 0, right: 0, height: Double(kBarHeight)) {
                        // The desktop's own menu-bar palette: near-black with
                        // a hairline under it, so it reads as chrome against
                        // any wallpaper. Near-black, not black — see above.
                        ColoredBox(color: Color(0xF01B1D22)) {
                            Padding(padding: EdgeInsets(left: 14, top: 0, right: 14, bottom: 0)) {
                                Row(crossAxisAlignment: .center) {
                                    for title in titles { titleChip(title) }
                                    Expanded { SizedBox(expand: ()) }
                                    Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 8) {
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
                    }
                    // ALWAYS emitted, empty when no menu is down, rather
                    // than added and removed with the menu.
                    //
                    // A Stack that GAINS a child does not composite the new
                    // one until something else remounts the subtree: the state
                    // flips, `build` runs, and the screen keeps the old frame —
                    // the first tap after startup did nothing at all, while the
                    // same tap after the focused app changed (which reshapes
                    // the title row) worked every time. Element remount is this
                    // framework's dominant update path; a constant child count
                    // sidesteps the question.
                    Positioned(left: menuAnchor(titles), top: Double(kBarHeight) - 3) {
                        openMenu(titles)
                    }
                }
            })
    }
}
#endif
