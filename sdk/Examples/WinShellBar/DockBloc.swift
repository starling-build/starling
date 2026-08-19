// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The dock's state, and everything slow that produces it.
//
// Same shape as the desktop's app blocs (SettingsBloc, TaskManagerBloc,
// FileExplorerBloc): one value-type `DockState`, one `Event` enum, and an
// `@Observable` bloc whose `add(_:)` is the only way the UI changes anything.
// The widget reads `bloc.state`, dispatches events, and rebuilds through
// `withObservationTracking`.
//
// It earns its place here for the reason the pattern exists at all: NOTHING
// SLOW MAY RUN ON THE UI THREAD, and this is where all of it lives. Reading
// the Start Menu is a few hundred `.lnk` files through COM; the status
// readout is COM and the WLAN API on a one-second timer; setting the volume,
// the Wi-Fi radio and the theme are each a system call; saving the pins is a
// file write. Every one of them is a `Task.detached` here, publishing back
// through `MainActor.run`, so the thread drawing the dock only ever assigns
// already-computed values.
//
// What stays in the widget is what is genuinely about this frame's pointer:
// which tile is hovered, whether a menu or the control centre is open,
// whether the volume slider is mid-drag. That is view state, not app state,
// and putting it here would mean a round trip through the bloc for every
// mouse move.

#if os(Windows)
import Flutter
import FlutterWin32
import FlutterWin32Bridge
import Foundation
import Observation

/// The single source of truth for the dock.
struct DockState {
    /// Everything installed, from the Start Menu.
    var catalog: [Win32App] = []
    /// Whether the Start Menu walk has finished. Until it has, the dock draws
    /// what is running and nothing else — which is right, and is why this is
    /// separate from `catalog.isEmpty`.
    var catalogReady = false
    /// The pinned keys, in dock order.
    var pins: [String] = []
    /// What the dock draws: pins first, then everything else with a window.
    var items: [DockItem] = []

    var now = Date()
    var network = Win32Network(kind: .none, signal: 0, ssid: "")
    var power = Win32Power(hasBattery: false, percent: nil, isCharging: true)
    var volume: Win32Volume?
    /// The monitor's backlight, or nil when no monitor answers DDC/CI — in
    /// which case the control centre does not draw the control at all.
    var brightness: Int?
    var darkMode = false
    /// Set by the Wi-Fi tile so the panel answers the click immediately — the
    /// radio takes a moment to settle and the next poll is a second away,
    /// which without this reads as a dead button. Cleared once the poll agrees.
    var wifiWanted: Bool?
    /// Whether the user has asked for Explorer's taskbar back.
    var nativeTaskbarWanted = false

    /// Bumped when an icon texture lands. Icons are rasterized off the UI
    /// thread and arrive after the tiles that want them are already drawn, so
    /// something observable has to change or the dock keeps its fallback
    /// glyphs for ever.
    var iconRevision = 0

    /// What the Wi-Fi tile should show. The poll is the truth; `wifiWanted`
    /// covers the second between the click and the radio settling.
    var wifiIsOn: Bool { wifiWanted ?? (network.kind == .wifi) }
}

@Observable
final class DockBloc: @unchecked Sendable {

    /// The events the UI dispatches.
    enum Event {
        /// Start loading. Sent once, from the dock's `initState`.
        case start
        /// The one-second heartbeat: clock, status, and Explorer's taskbar.
        case tick
        /// A window opened, closed, or changed — from the WinEvent hook.
        case windowsChanged

        /// A dock icon was pressed: start it, raise it, or put it away.
        case activate(DockItem)
        case togglePin(DockItem)
        case closeAll(DockItem)

        case setVolume(Int)
        case setBrightness(Int)
        case toggleMute
        case toggleWifi
        case toggleDarkMode
        case setNativeTaskbar(Bool)

        // Completions, dispatched by the bloc's own background work. They are
        // events like any other so that every mutation goes through `add`.
        case catalogLoaded([Win32App])
        case statusRead(network: Win32Network, power: Win32Power,
                        volume: Win32Volume?, dark: Bool)
        case iconsChanged
    }

    private(set) var state = DockState()

    /// Icon textures. Owned here because `rebuild` is what asks for them, and
    /// exposed because only the widget can turn one into a `TextureWidget`.
    @ObservationIgnored let icons = IconCache()

    @ObservationIgnored private var refreshQueued = false
    /// True once `pins` holds real values — either the file was read, or the
    /// catalog arrived and the defaults were resolved against it.
    @ObservationIgnored private var pinsAreSeeded = false

    @ObservationIgnored private var pinsPath: String {
        let base = ProcessInfo.processInfo.environment["APPDATA"]
            ?? NSTemporaryDirectory()
        return base + "\\Starling\\dock.txt"
    }

    // MARK: - Dispatch

    func add(_ event: Event) {
        switch event {
        case .start:
            _start()
        case .tick:
            state.now = Date()
            _hideNativeTaskbarIfItCameBack()
            _readStatus()
        case .windowsChanged:
            _queueRefresh()

        case .catalogLoaded(let apps):
            state.catalog = apps
            state.catalogReady = true
            // The first-run defaults are resolved BY NAME out of the catalog,
            // so they could not have been seeded any earlier than this.
            if !pinsAreSeeded {
                state.pins = _defaultPins(from: apps)
                pinsAreSeeded = true
            }
            print("[WinShellDock] \(apps.count) apps in the Start Menu, "
                  + "\(state.pins.count) pinned")
            _rebuild()

        case .statusRead(let network, let power, let volume, let dark):
            state.network = network
            state.power = power
            state.volume = volume
            state.darkMode = dark
            // The poll is the truth. Drop the optimistic Wi-Fi answer as soon
            // as it agrees, so a radio that refused the change corrects itself
            // instead of leaving the tile lying about it.
            if let wanted = state.wifiWanted, (network.kind == .wifi) == wanted {
                state.wifiWanted = nil
            }

        case .iconsChanged:
            state.iconRevision &+= 1

        case .activate(let item):
            _activate(item)
        case .togglePin(let item):
            if let at = state.pins.firstIndex(of: item.key) {
                state.pins.remove(at: at)
            } else {
                state.pins.append(item.key)
            }
            _savePins(state.pins)
            _rebuild()
        case .closeAll(let item):
            let handles = item.windows.map { $0.handle }
            Task.detached {
                for handle in handles { Win32WindowManager.close(handle) }
            }
            _queueRefresh()

        case .setBrightness(let percent):
            // Optimistic so the slider tracks the drag. NOT re-read after:
            // every read is an I2C round trip to the monitor, and a drag
            // would queue dozens of them behind each other.
            state.brightness = percent
            Task.detached { Win32Control.setBrightness(percent) }

        case .setVolume(let percent):
            // Optimistic so the slider tracks the drag; the next poll re-reads
            // what the mixer actually accepted.
            state.volume = Win32Volume(percent: percent, isMuted: percent == 0)
            Task.detached { Win32Control.setVolume(percent) }
        case .toggleMute:
            let muted = !(state.volume?.isMuted ?? false)
            state.volume = Win32Volume(percent: state.volume?.percent ?? 0,
                                       isMuted: muted)
            Task.detached { Win32Control.setMuted(muted) }
        case .toggleWifi:
            let on = !state.wifiIsOn
            state.wifiWanted = on
            Task.detached { [weak self] in
                let ok = Win32Control.setWifiRadio(on)
                if !ok {
                    await MainActor.run { self?.state.wifiWanted = nil }
                }
            }
        case .toggleDarkMode:
            let dark = !state.darkMode
            state.darkMode = dark
            Task.detached { Win32Control.setDarkMode(dark) }
        case .setNativeTaskbar(let wanted):
            state.nativeTaskbarWanted = wanted
            Task.detached {
                if wanted {
                    Win32Shell.showNativeTaskbar()
                } else {
                    _ = Win32Shell.hideNativeTaskbar()
                }
            }
        }
    }

    // MARK: - Handlers

    private func _start() {
        icons.onTextureReady = { [weak self] in self?.add(.iconsChanged) }

        // The pins file, if there is one. The DEFAULTS need the catalog and
        // are seeded in `.catalogLoaded`.
        if let stored = _loadPins() {
            state.pins = stored
            pinsAreSeeded = true
        }

        // The Start Menu walk is a few hundred .lnk files through COM. On the
        // UI thread it measured 1408ms — a dock that is not on screen for a
        // second and a half after login — against ~200ms here, because this
        // thread is not also pumping messages and rendering.
        Task.detached { [weak self] in
            let apps = Win32AppCatalog.apps()
            await MainActor.run { self?.add(.catalogLoaded(apps)) }
        }

        _rebuild()
        _readStatus()

        // Once, not on the tick. Reading the backlight is an I2C round trip
        // to the monitor's firmware; asking every second would be rude to the
        // hardware and buys nothing, because nothing changes it but us.
        Task.detached { [weak self] in
            let level = Win32Status.brightness()
            await MainActor.run { self?.state.brightness = level }
        }
    }

    /// Reads the system status off the UI thread and publishes it back.
    ///
    /// Small on this machine — 4-9ms a tick — but it is COM and the WLAN API,
    /// on a timer, on the thread that draws. `WlanQueryInterface` on a machine
    /// with a wireless adapter is not bounded by anything we control, and a
    /// dock that stutters once a second is what that looks like.
    private func _readStatus() {
        Task.detached { [weak self] in
            let network = Win32Status.network()
            let power = Win32Status.power()
            let volume = Win32Status.volume()
            // Read rather than remembered: the user can change the theme in
            // Windows' own Settings and the tile has to follow.
            let dark = Win32Control.isDarkMode
            await MainActor.run {
                self?.add(.statusRead(network: network, power: power,
                                      volume: volume, dark: dark))
            }
        }
    }

    /// Explorer puts its taskbar back on its own — a display change, a
    /// Settings round trip, or explorer restarting after a crash all do it,
    /// and none of them tell us. The EVENT_OBJECT_SHOW hook catches the fast
    /// case; this catches a new explorer pid.
    private func _hideNativeTaskbarIfItCameBack() {
        guard !keepsNativeTaskbar, !state.nativeTaskbarWanted else { return }
        Task.detached {
            if Win32Shell.nativeTaskbarIsVisible { _ = Win32Shell.hideNativeTaskbar() }
        }
    }

    private func _activate(_ item: DockItem) {
        // The launcher is a different PROCESS — one widget root per process —
        // so pressing it is a broadcast, not a call.
        guard item.key != kLauncherKey else {
            Win32Shell.toggleOverlay()
            return
        }
        guard let window = item.windows.first(where: { $0.isForeground })
                ?? item.windows.first else {
            if let app = item.app {
                // Off the UI thread: the fast path is 8ms but the `.lnk`
                // fallback measured 484ms, and this thread has frames to draw.
                Task.detached { Win32AppCatalog.launch(app) }
            }
            return
        }
        if window.isForeground {
            Win32WindowManager.minimize(window.handle)
        } else {
            Win32WindowManager.activate(window.handle)
        }
        _queueRefresh()
    }

    /// Coalesces refreshes: a burst of window events is one rebuild.
    private func _queueRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            refreshQueued = false
            _rebuild()
        }
    }

    /// Recomputes `items` from the pins, the catalog and the live windows.
    ///
    /// Cheap and synchronous on purpose — window enumeration measured under a
    /// millisecond, and the icons it asks for rasterize on their own queue.
    private func _rebuild() {
        let windows = Win32WindowManager.windows()
        var byExe: [String: [Win32Window]] = [:]
        for window in windows {
            byExe[IconCache.key(for: window), default: []].append(window)
        }

        var built: [DockItem] = []
        var claimed: Set<String> = []

        for key in state.pins {
            guard !claimed.contains(key) else { continue }
            claimed.insert(key)
            let app = state.catalog.first(where: { IconCache.key(for: $0) == key })
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
            let app = state.catalog.first(where: { IconCache.key(for: $0) == key })
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
        state.items = [DockItem(key: kLauncherKey, name: "Launcher", app: nil,
                                windows: [], isPinned: true)] + built
    }

    // MARK: - Pins

    /// The stored pins, or nil when there is no file yet.
    ///
    /// Nil rather than "the defaults", because the defaults are resolved
    /// against the CATALOG, and the catalog is read off the UI thread and
    /// arrives later. Returning the defaults here would resolve them against
    /// an empty catalog and seed nothing at all — a dock with no icons on a
    /// new machine, and no clue why.
    private func _loadPins() -> [String]? {
        guard let text = try? String(contentsOfFile: pinsPath, encoding: .utf8) else {
            return nil
        }
        return text.split(whereSeparator: { $0 == "\r\n" || $0 == "\n" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// First run: what to pin, resolved against what is actually installed, so
    /// the dock is never empty on a new machine.
    private func _defaultPins(from catalog: [Win32App]) -> [String] {
        kDefaultPins.compactMap { wanted in
            catalog.first(where: { $0.name.lowercased().contains(wanted) })
                .map { IconCache.key(for: $0) }
        }
    }

    /// A file write, so it goes off the thread that draws like everything else.
    private func _savePins(_ pins: [String]) {
        let path = pinsPath
        Task.detached {
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir,
                                                     withIntermediateDirectories: true)
            try? pins.joined(separator: "\r\n").write(toFile: path, atomically: true,
                                                      encoding: .utf8)
        }
    }
}

/// The dock's bloc. One surface per process, so one instance.
let dockBloc = DockBloc()
#endif
