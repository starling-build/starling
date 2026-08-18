// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import Foundation
import Observation
import StarlingAudio
import StarlingNet
import StarlingPower
import StarlingRegistry
import StarlingTime

/// Set by _SettingsAppState so the themed root can sync the Dark Mode
/// switch when the shell pushes an appearance change.
nonisolated(unsafe) var settingsBlocShared: SettingsBloc?

// MARK: - Settings State

/// `SettingsApp --pane=<name>` opens on that pane — the deep link the
/// shell's "Network Settings…" popup row uses (--pane=network). An unknown
/// or absent pane falls through to General.
func initialPaneIndex() -> Int {
    let panes = ["general": 0, "network": 1, "displays": 2, "sound": 3,
                 "datetime": 4, "defaultapps": 5, "appearance": 6,
                 "power": 7, "sharing": 8, "about": 9]
    for arg in CommandLine.arguments.dropFirst() {
        if arg.hasPrefix("--pane="),
           let idx = panes[String(arg.dropFirst("--pane=".count)).lowercased()] {
            return idx
        }
    }
    return 0
}

struct SettingsState {
    // Navigation
    var selectedIndex: Int = initialPaneIndex()

    // System Info
    var osVersion: String = ""
    var kernelVersion: String = ""
    var mesaVersion: String = ""

    // Network
    var wifiEnabled: Bool = false
    var wifiNetworks: [WifiNetwork] = []
    var connectionInfo: WifiConnectionInfo? = nil
    var savedConnections: [String] = []
    var networkStatus: String? = nil
    /// Every managed wired interface — this pane is the detailed view, so it
    /// lists them all where the shell's popup shows only the primary one.
    var wiredLinks: [WiredStatus] = []

    // Display
    var dpiValue: Double = SystemInfo.currentDPI()

    /// The connected displays, as the shell reports them. Empty on the hosts
    /// that push no list (the windowed dev host), which is what the pane keys
    /// off to fall back to describing the one screen it can see.
    #if os(Linux)
    var displays: [GpuDmaBufRenderer.DisplayInfo] =
        GpuDmaBufRenderer.lastPushedDisplays ?? []
    #endif

    // Personalization. The shell owns the desktop appearance and pushes it at
    // connect, before this bloc exists — seed from it so the Dark Mode switch
    // agrees with the theme the app is actually drawn in.
    #if os(Linux)
    var darkMode: Bool = GpuDmaBufRenderer.lastPushedThemeIsDark ?? true
    /// Window-manager layout — the shell owns it and pushes at connect.
    var tilingWM: Bool = GpuDmaBufRenderer.lastPushedLayoutIsTiling ?? false
    /// Wallpaper preset raw value — the shell owns it and pushes at connect.
    var wallpaper: Int = GpuDmaBufRenderer.lastPushedWallpaper ?? 0
    /// Screensaver idle timeout in seconds (0 = never) — the shell owns it
    /// and pushes at connect.
    var screensaverIdle: Int = GpuDmaBufRenderer.lastPushedScreensaver ?? 600
    /// Remote desktop, as the shell reports it — never as the switch was
    /// last clicked. A start that fails leaves this false.
    var rdpEnabled: Bool = GpuDmaBufRenderer.lastPushedRdpEnabled ?? false
    #else
    var darkMode: Bool = true
    var tilingWM: Bool = false
    var wallpaper: Int = 0
    var screensaverIdle: Int = 600
    #endif

    // Power. Seeded synchronously — a handful of sysfs reads — so the pane
    // never draws a made-up default; refreshed on a 5s tick while visible.
    var battery: BatteryStatus = BatteryReader.read()
    var backlight: BacklightStatus = BacklightControl.read()
    /// logind's refusal from the last brightness write (an SSH-launched
    /// session owns no seat devices) — shown verbatim, like timeError.
    var powerError: String? = nil

    // Sound. Seeded empty (available=false), NOT synchronously: status()
    // spawns wpctl twice, too heavy for state init on the main thread.
    // _loadInitialData fills it off-main before the pane can be reached.
    var audio = AudioStatus()

    // Default Apps. Candidates are the installed records declaring
    // UrlSchemes=http — the same filter the xdg-open shim applies, read
    // from the same registry, so the pane can only offer what the shim
    // would actually launch.
    var browserCandidates: [(id: String, name: String)] = []
    /// The effective default browser id: the configured choice when it is
    /// still a candidate, else the first candidate — mirroring the shim.
    var defaultBrowser = ""

    // Date & Time. Same contract as audio: seeded empty, filled off-main.
    var time = TimeStatus()
    /// The zone list, loaded once when the picker first opens (485 rows).
    var timezones: [String] = []
    var tzPickerOpen = false
    /// nil = picking a region; set = picking a city within it.
    var tzPickerRegion: String? = nil
    /// polkit's refusal (or any tool error) from the last mutation — shown
    /// under the pane verbatim. A seat-active session never sees one; an
    /// SSH-launched dev desktop always does, and that difference is real.
    var timeError: String? = nil
}

// MARK: - Settings Events

enum SettingsEvent {
    // Lifecycle
    case loadInitialData

    // Navigation
    case selectTab(Int)

    // Network
    case toggleWifi(Bool)
    case scanNetworks
    case setWiredConnected(device: String, connected: Bool)
    case connectToNetwork(ssid: String, password: String?)
    case disconnect(connectionName: String)
    case forgetNetwork(connectionName: String)

    // Display
    case changeDpi(Double)
    /// Make this display the primary one — where the dock lives and new
    /// windows open. The value is the output id the shell reported.
    case selectPrimaryDisplay(Int)
    #if os(Linux)
    /// Display list pushed by the shell (no echo back).
    case displaysApplied([GpuDmaBufRenderer.DisplayInfo])
    #endif
    /// Move the thumb without touching the desktop — see `_applyDpi`.
    case previewDpi(Double)

    // Personalization
    case toggleDarkMode(Bool)
    /// Appearance pushed by the shell (no echo back).
    case themeApplied(Bool)
    case toggleTilingWM(Bool)
    /// Layout pushed by the shell (no echo back).
    case layoutApplied(Bool)
    case selectWallpaper(Int)
    /// Wallpaper pushed by the shell (no echo back).
    case wallpaperApplied(Int)
    /// Screensaver idle timeout in seconds; 0 = never.
    case selectScreensaverIdle(Int)
    /// Idle timeout pushed by the shell (no echo back).
    case screensaverApplied(Int)

    // Sharing (remote desktop)
    case toggleRdp(Bool)
    case rdpApplied(Bool)

    // Power
    case refreshBattery
    case changeBrightness(Int)

    // Sound
    case refreshAudio
    case changeVolume(Double)
    case toggleMute(Bool)
    case selectSink(Int)

    // Date & Time
    case refreshTime
    case toggleNTP(Bool)
    case setTzPicker(open: Bool, region: String?)
    case selectTimezone(String)

    // Default Apps
    case refreshDefaultApps
    case selectBrowser(String)
}

// MARK: - Settings BLoC

@Observable
final class SettingsBloc: @unchecked Sendable {

    /// The single source of truth for the UI.
    private(set) var state = SettingsState()

    /// The only way the UI talks to the BLoC.
    func add(_ event: SettingsEvent) {
        switch event {
        case .loadInitialData:
            _loadInitialData()
            if state.selectedIndex == Self.powerPaneIndex { _refreshBattery() }
            if state.selectedIndex == Self.soundPaneIndex { _refreshAudio() }
            if state.selectedIndex == Self.dateTimePaneIndex { _refreshTime() }
            if state.selectedIndex == Self.defaultAppsPaneIndex { _refreshDefaultApps() }
        case .selectTab(let index):
            state.selectedIndex = index
            if index == Self.powerPaneIndex { _refreshBattery() }
            if index == Self.soundPaneIndex { _refreshAudio() }
            if index == Self.dateTimePaneIndex { _refreshTime() }
            if index == Self.defaultAppsPaneIndex { _refreshDefaultApps() }
        case .toggleWifi(let enabled):
            _toggleWifi(enabled)
        case .scanNetworks:
            _scanNetworks()
        case .setWiredConnected(let device, let connected):
            _setWiredConnected(device: device, connected: connected)
        case .connectToNetwork(let ssid, let password):
            _connectToNetwork(ssid: ssid, password: password)
        case .disconnect(let name):
            _disconnect(connectionName: name)
        case .forgetNetwork(let name):
            _forgetNetwork(connectionName: name)
        case .changeDpi(let value):
            state.dpiValue = value
            _applyDpi(value)
        case .selectPrimaryDisplay(let outputId):
            // Optimistic, like the wallpaper picker: the shell echoes the new
            // list back and `displaysApplied` is what makes it stick, so a
            // refused pick reverts on the next push instead of lying.
            #if os(Linux)
            state.displays = state.displays.map {
                GpuDmaBufRenderer.DisplayInfo(
                    id: $0.id, name: $0.name,
                    physicalWidth: $0.physicalWidth,
                    physicalHeight: $0.physicalHeight,
                    scale: $0.scale, isPrimary: $0.id == outputId)
            }
            #endif
            _applyPrimaryDisplay(outputId)
        #if os(Linux)
        case .displaysApplied(let displays):
            state.displays = displays
        #endif
        case .previewDpi(let value):
            state.dpiValue = value
        case .toggleDarkMode(let value):
            state.darkMode = value
            _applyTheme(value)
        case .themeApplied(let value):
            state.darkMode = value
        case .toggleTilingWM(let value):
            state.tilingWM = value
            _applyLayout(value)
        case .layoutApplied(let value):
            state.tilingWM = value
        case .selectWallpaper(let value):
            state.wallpaper = value
            _applyWallpaper(value)
        case .wallpaperApplied(let value):
            state.wallpaper = value
        case .selectScreensaverIdle(let value):
            state.screensaverIdle = value
            _applyScreensaver(value)
        case .screensaverApplied(let value):
            state.screensaverIdle = value
        case .toggleRdp(let value):
            // Deliberately NOT optimistic: the shell answers with what the
            // listener actually did, and a switch that flicked on and back
            // off is the honest report of a failed start.
            _applyRdp(value)
        case .rdpApplied(let enabled):
            state.rdpEnabled = enabled
        case .refreshBattery:
            _refreshBattery()
        case .changeBrightness(let percent):
            // Optimistic raw update so the slider tracks the drag; the tick
            // re-reads what the kernel actually accepted.
            let pct = min(max(percent, 1), 100)
            let scale = Double(state.backlight.maxBrightness) / 100.0
            let raw = Int((Double(pct) * scale).rounded())
            state.backlight.brightness = max(1, raw)
            _applyBrightness(percent)
        case .refreshAudio:
            _refreshAudio()
        case .changeVolume(let value):
            state.audio.volume = value
            _applyVolume(value)
        case .toggleMute(let value):
            state.audio.muted = value
            _applyMute(value)
        case .selectSink(let id):
            _selectSink(id)
        case .refreshTime:
            _refreshTime()
        case .toggleNTP(let value):
            state.time.ntpEnabled = value
            _applyNTP(value)
        case .setTzPicker(let open, let region):
            state.tzPickerOpen = open
            state.tzPickerRegion = region
            if open && state.timezones.isEmpty { _loadTimezones() }
        case .selectTimezone(let zone):
            state.tzPickerOpen = false
            state.tzPickerRegion = nil
            _applyTimezone(zone)
        case .refreshDefaultApps:
            _refreshDefaultApps()
        case .selectBrowser(let id):
            state.defaultBrowser = id
            _applyBrowser(id)
        }
    }

    /// Sidebar indices (see initialPaneIndex's table).
    static let soundPaneIndex = 3
    static let dateTimePaneIndex = 4
    static let defaultAppsPaneIndex = 5
    static let powerPaneIndex = 7

    // MARK: - Event Handlers

    private func _loadInitialData() {
        // Load on background thread to avoid blocking the first frame.
        Task.detached {
            let os = SystemInfo.osVersion()
            let kernel = SystemInfo.kernelVersion()
            let mesa = SystemInfo.mesaVersion()
            #if os(Linux)
            let wifiOn = WifiManager.isWifiEnabled()
            let networks = wifiOn ? WifiManager.listNetworks() : [WifiNetwork]()
            let connInfo = wifiOn ? WifiManager.activeConnectionInfo() : nil
            let saved = wifiOn ? WifiManager.savedConnections() : [String]()
            let wired = EthernetManager.statuses()
            #endif
            let audio = AudioControl.status()
            await MainActor.run { [self] in
                state.osVersion = os
                state.kernelVersion = kernel
                state.mesaVersion = mesa
                #if os(Linux)
                state.wifiEnabled = wifiOn
                state.wifiNetworks = networks
                state.connectionInfo = connInfo
                state.savedConnections = saved
                state.wiredLinks = wired
                #endif
                state.audio = audio
            }
        }
    }

    private func _setWiredConnected(device: String, connected: Bool) {
        state.networkStatus = connected
            ? "Connecting \(device)..." : "Disconnecting \(device)..."
        Task.detached {
            let error = connected
                ? EthernetManager.connect(device: device)
                : EthernetManager.disconnect(device: device)
            let wired = EthernetManager.statuses()
            await MainActor.run { [self] in
                state.networkStatus = error
                state.wiredLinks = wired
            }
        }
    }

    private func _toggleWifi(_ enabled: Bool) {
        state.wifiEnabled = enabled
        if !enabled {
            state.wifiNetworks = []
            state.connectionInfo = nil
        }
        Task.detached {
            _ = WifiManager.setWifiEnabled(enabled)
            if enabled {
                let networks = WifiManager.listNetworks()
                let info = WifiManager.activeConnectionInfo()
                await MainActor.run { [self] in
                    state.wifiNetworks = networks
                    state.connectionInfo = info
                }
            }
        }
    }

    private func _scanNetworks() {
        state.networkStatus = "Scanning..."
        Task.detached {
            let networks = WifiManager.scanAndListNetworks()
            let info = WifiManager.activeConnectionInfo()
            let wired = EthernetManager.statuses()
            await MainActor.run { [self] in
                state.wifiNetworks = networks
                state.connectionInfo = info
                state.wiredLinks = wired
                state.networkStatus = nil
            }
        }
    }

    private func _connectToNetwork(ssid: String, password: String?) {
        // The scan result's SECURITY string picks the key management for a
        // new profile (WPA3-only APs need SAE).
        let security = state.wifiNetworks.first { $0.ssid == ssid }?.security ?? ""
        state.networkStatus = "Connecting to \(ssid)..."
        Task.detached {
            let error = WifiManager.connect(ssid: ssid, password: password,
                                            security: security)
            let networks = WifiManager.listNetworks()
            let info = WifiManager.activeConnectionInfo()
            let saved = WifiManager.savedConnections()
            await MainActor.run { [self] in
                state.networkStatus = error.map {
                    WifiManager.friendlyConnectError($0)
                }
                state.wifiNetworks = networks
                state.connectionInfo = info
                state.savedConnections = saved
            }
        }
    }

    private func _disconnect(connectionName: String) {
        state.connectionInfo = nil
        state.networkStatus = "Disconnecting..."
        Task.detached {
            let _ = WifiManager.disconnect(connectionName: connectionName)
            let networks = WifiManager.listNetworks()
            let info = WifiManager.activeConnectionInfo()
            let saved = WifiManager.savedConnections()
            await MainActor.run { [self] in
                state.wifiNetworks = networks
                state.connectionInfo = info
                state.savedConnections = saved
                state.networkStatus = nil
            }
        }
    }

    /// Apply a scale to the whole desktop. Called ONCE per gesture, from the
    /// slider's `onChangeEnd` — never from `onChanged`.
    ///
    /// A DPI change rescales every surface on screen, this window among them,
    /// so applying one mid-drag moves the slider out from under the finger:
    /// the next drag update measures against the new geometry, picks a value
    /// far from the intended one, and rescales again. Dragging toward 1.75
    /// went 1.75 → 1.25 → 2.0 → 1.25 → 2.0 and settled on 1.25 — the value
    /// the feedback loop stopped on, not the one aimed at. That thrash is
    /// what made fractional scales look unreachable; the scales themselves
    /// always rendered fine. `previewDpi` moves the thumb during the drag.
    private func _applyDpi(_ dpi: Double) {
        #if os(Linux)
        GpuDmaBufRenderer.current?.sendDpiChange(dpi)
        #endif
    }

    /// Forward the primary-display pick to the shell, which moves the dock,
    /// re-orders the wl_outputs, persists the choice, and pushes the new list
    /// back to every child.
    private func _applyPrimaryDisplay(_ outputId: Int) {
        #if os(Linux)
        GpuDmaBufRenderer.current?.sendPrimaryDisplayChange(outputId: outputId)
        #endif
    }

    /// Forward the Dark Mode toggle to the shell, which switches the
    /// desktop appearance and persists it.
    private func _applyTheme(_ dark: Bool) {
        #if os(Linux)
        GpuDmaBufRenderer.current?.sendThemeChange(dark: dark)
        #endif
    }

    /// Forward the Tiling Windows toggle to the shell, which switches the
    /// window manager and persists it.
    private func _applyLayout(_ tiling: Bool) {
        #if os(Linux)
        GpuDmaBufRenderer.current?.sendLayoutChange(tiling: tiling)
        #endif
    }

    private func _forgetNetwork(connectionName: String) {
        state.networkStatus = "Forgetting \"\(connectionName)\"..."
        Task.detached {
            let _ = WifiManager.forget(connectionName: connectionName)
            // Forgetting the active network disconnects it — refresh
            // everything the pane shows, not just the saved list.
            let saved = WifiManager.savedConnections()
            let networks = WifiManager.listNetworks()
            let info = WifiManager.activeConnectionInfo()
            await MainActor.run { [self] in
                state.savedConnections = saved
                state.wifiNetworks = networks
                state.connectionInfo = info
                state.networkStatus = "Forgot \"\(connectionName)\""
            }
        }
    }

    /// Forward the wallpaper pick to the shell, which repaints, persists,
    /// and pushes the choice back to every child.
    private func _applyWallpaper(_ preset: Int) {
        #if os(Linux)
        GpuDmaBufRenderer.current?.sendWallpaperChange(preset: preset)
        #endif
    }

    /// Forward the Screensaver picker to the shell, which restarts its idle
    /// timer and persists the choice.
    private func _applyScreensaver(_ seconds: Int) {
        #if os(Linux)
        GpuDmaBufRenderer.current?.sendScreensaverChange(seconds: seconds)
        #endif
    }

    // MARK: - Sharing (remote desktop)

    private func _applyRdp(_ enabled: Bool) {
        #if os(Linux)
        GpuDmaBufRenderer.current?.sendRdpChange(enabled: enabled)
        #endif
    }


    // MARK: - Battery

    /// Re-read sysfs off the main thread (a misbehaving driver can stall a
    /// read), then keep a 5s tick alive while the Power pane is the one on
    /// screen. Leaving the pane lets the pending tick fire once and lapse.
    private var _batteryTickScheduled = false

    private func _refreshBattery() {
        Task.detached {
            let status = BatteryReader.read()
            let backlight = BacklightControl.read()
            await MainActor.run { [self] in
                state.battery = status
                state.backlight = backlight
                _scheduleBatteryTick()
            }
        }
    }

    private func _applyBrightness(_ percent: Int) {
        let current = state.backlight
        Task.detached {
            let error = BacklightControl.setPercent(percent, status: current)
            await MainActor.run { [self] in state.powerError = error }
        }
    }

    private func _scheduleBatteryTick() {
        guard state.selectedIndex == Self.powerPaneIndex,
              !_batteryTickScheduled else { return }
        _batteryTickScheduled = true
        let work: () -> Void = { [weak self] in
            guard let self else { return }
            self._batteryTickScheduled = false
            guard self.state.selectedIndex == Self.powerPaneIndex else { return }
            self.add(.refreshBattery)
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 5,
            execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }

    // MARK: - Sound

    /// Same shape as the battery: re-read off-main, tick while the pane is
    /// the one on screen so volume moved elsewhere (a keyboard key, wpctl
    /// by hand) shows up here.
    private var _audioTickScheduled = false

    private func _refreshAudio() {
        Task.detached {
            let status = AudioControl.status()
            await MainActor.run { [self] in
                state.audio = status
                _scheduleAudioTick()
            }
        }
    }

    private func _scheduleAudioTick() {
        guard state.selectedIndex == Self.soundPaneIndex,
              !_audioTickScheduled else { return }
        _audioTickScheduled = true
        let work: () -> Void = { [weak self] in
            guard let self else { return }
            self._audioTickScheduled = false
            guard self.state.selectedIndex == Self.soundPaneIndex else { return }
            self.add(.refreshAudio)
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 5,
            execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }

    private func _applyVolume(_ volume: Double) {
        Task.detached { AudioControl.setVolume(volume) }
    }

    private func _applyMute(_ muted: Bool) {
        Task.detached { AudioControl.setMuted(muted) }
    }

    private func _selectSink(_ id: Int) {
        Task.detached {
            AudioControl.setDefaultSink(id: id)
            let status = AudioControl.status()
            await MainActor.run { [self] in state.audio = status }
        }
    }

    // MARK: - Date & Time

    /// Same shape as the battery and audio: re-read off-main, tick while
    /// the pane is on screen so the clock line and sync state stay current.
    private var _timeTickScheduled = false

    private func _refreshTime() {
        Task.detached {
            let status = TimeControl.status()
            await MainActor.run { [self] in
                state.time = status
                _scheduleTimeTick()
            }
        }
    }

    private func _scheduleTimeTick() {
        guard state.selectedIndex == Self.dateTimePaneIndex,
              !_timeTickScheduled else { return }
        _timeTickScheduled = true
        let work: () -> Void = { [weak self] in
            guard let self else { return }
            self._timeTickScheduled = false
            guard self.state.selectedIndex == Self.dateTimePaneIndex else { return }
            self.add(.refreshTime)
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 5,
            execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }

    private func _loadTimezones() {
        Task.detached {
            let zones = TimeControl.listTimezones()
            await MainActor.run { [self] in state.timezones = zones }
        }
    }

    private func _applyNTP(_ enabled: Bool) {
        Task.detached {
            let error = TimeControl.setNTP(enabled)
            let status = TimeControl.status()
            await MainActor.run { [self] in
                state.timeError = error
                // The refresh is what reverts the switch on a refusal —
                // the pane shows what the system did, not what was asked.
                state.time = status
            }
        }
    }

    private func _applyTimezone(_ zone: String) {
        Task.detached {
            let error = TimeControl.setTimezone(zone)
            let status = TimeControl.status()
            await MainActor.run { [self] in
                state.timeError = error
                state.time = status
            }
        }
    }

    // MARK: - Default Apps

    /// `browser=<id>` in this file picks among the http-claiming records —
    /// the xdg-open shim reads the same line from the same path.
    private static var _defaultAppsFile: String {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            ?? (NSHomeDirectory() + "/.config")
        return base + "/starling/default-apps"
    }

    private func _refreshDefaultApps() {
        Task.detached {
            let candidates = AppRegistry.shared.installedApps
                .filter { $0.urlSchemes.contains("http") }
                .map { (id: $0.id, name: $0.name) }
            let configured = (try? String(contentsOfFile: Self._defaultAppsFile,
                                          encoding: .utf8))?
                .split(separator: "\n")
                .first { $0.hasPrefix("browser=") }
                .map { String($0.dropFirst("browser=".count)) }
            let effective = candidates.first { $0.id == configured }?.id
                ?? candidates.first?.id ?? ""
            await MainActor.run { [self] in
                state.browserCandidates = candidates
                state.defaultBrowser = effective
            }
        }
    }

    /// Rewrite only the browser line; anything else in the file (a future
    /// `editor=`) survives untouched.
    private func _applyBrowser(_ id: String) {
        Task.detached {
            let path = Self._defaultAppsFile
            var lines = ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
                .split(separator: "\n").map(String.init)
                .filter { !$0.hasPrefix("browser=") }
            lines.append("browser=\(id)")
            try? FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            try? (lines.joined(separator: "\n") + "\n")
                .write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
