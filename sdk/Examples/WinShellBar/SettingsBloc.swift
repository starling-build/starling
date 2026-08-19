// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Settings app's state, and everything slow that produces it.
//
// Same shape as DockBloc and the desktop's own SettingsBloc: one value-type
// state, one Event enum, `add(_:)` the only mutator, read back through
// `withObservationTracking`.
//
// Every reader here is slower than it looks — registry values, display-mode
// enumeration, disk geometry, an audio endpoint through COM — and two of the
// writers (the display mode, the wallpaper) reach the whole desktop. So the
// pattern is not decoration: a Settings app that gathers this on the UI thread
// is a Settings app that hangs for a moment every time you click a pane.

#if os(Windows)
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import FlutterWin32Bridge
import Foundation
import Observation

/// Which pane is showing. The order the sidebar lists them in.
enum SettingsPane: Int, CaseIterable {
    case system = 0
    case network
    case display
    case sound
    case personalisation
    case storage

    var title: String {
        switch self {
        case .system: return "System"
        case .network: return "Network"
        case .display: return "Display"
        case .sound: return "Sound"
        case .personalisation: return "Personalisation"
        case .storage: return "Storage"
        }
    }

    var icon: IconData {
        switch self {
        case .system: return CupertinoIcons.desktopcomputer
        case .network: return CupertinoIcons.antenna_radiowaves_left_right
        case .display: return CupertinoIcons.rectangle_on_rectangle
        case .sound: return CupertinoIcons.speaker_2_fill
        case .personalisation: return CupertinoIcons.paintbrush_fill
        case .storage: return CupertinoIcons.tray_2_fill
        }
    }

    /// The tile hue behind the icon, in the same muted band as the dock's.
    var tint: Color {
        switch self {
        case .system: return Color(0xFF737B89)
        case .network: return Color(0xFF5C8FD6)
        case .display: return Color(0xFF4880C8)
        case .sound: return Color(0xFFC9884E)
        case .personalisation: return Color(0xFF7B8FD0)
        case .storage: return Color(0xFF5CA0A8)
        }
    }
}

struct SettingsState {
    var pane: SettingsPane = .system

    /// nil until the first pass lands — the pane says it is loading rather
    /// than drawing zeroes that look like answers.
    var machine: Win32MachineInfo?
    var modes: [Win32DisplayMode] = []
    var currentMode: Win32DisplayMode?
    var brightness: Int?
    var volume: Win32Volume?
    var darkMode = false
    var drives: [Win32Drive] = []
    var wallpaper = ""
    var adapters: [Win32Adapter] = []

    /// What the last write did, shown verbatim. A display mode the adapter
    /// refuses is the one thing here that fails often enough to need saying.
    var notice: String?
}

@Observable
final class SettingsBloc: @unchecked Sendable {

    enum Event {
        case start
        case show(SettingsPane)
        case refresh

        case setBrightness(Int)
        case setVolume(Int)
        case toggleMute
        case toggleDarkMode
        case setDisplayMode(Win32DisplayMode)
        case pickWallpaper
        /// Windows' own Ethernet page, for the changes that need elevation.
        case openNetworkSettings

        // Completions.
        case loaded(machine: Win32MachineInfo, modes: [Win32DisplayMode],
                    current: Win32DisplayMode?, brightness: Int?,
                    volume: Win32Volume?, dark: Bool, drives: [Win32Drive],
                    wallpaper: String, adapters: [Win32Adapter])
        case notice(String?)
    }

    private(set) var state = SettingsState()

    func add(_ event: Event) {
        switch event {
        case .start, .refresh:
            _load()
        case .show(let pane):
            state.pane = pane

        case .loaded(let machine, let modes, let current, let brightness,
                     let volume, let dark, let drives, let wallpaper,
                     let adapters):
            state.machine = machine
            state.modes = modes
            state.currentMode = current
            state.brightness = brightness
            state.volume = volume
            state.darkMode = dark
            state.drives = drives
            state.wallpaper = wallpaper
            state.adapters = adapters

        case .notice(let text):
            state.notice = text

        case .setBrightness(let percent):
            state.brightness = percent
            Task.detached { Win32Control.setBrightness(percent) }
        case .setVolume(let percent):
            state.volume = Win32Volume(percent: percent, isMuted: percent == 0)
            Task.detached { Win32Control.setVolume(percent) }
        case .toggleMute:
            let muted = !(state.volume?.isMuted ?? false)
            state.volume = Win32Volume(percent: state.volume?.percent ?? 0,
                                       isMuted: muted)
            Task.detached { Win32Control.setMuted(muted) }
        case .toggleDarkMode:
            let dark = !state.darkMode
            state.darkMode = dark
            Task.detached { Win32Control.setDarkMode(dark) }

        case .setDisplayMode(let mode):
            // Optimistic, then corrected: a mode the adapter refuses leaves
            // the screen exactly as it was, and the pane has to say so rather
            // than showing a selection that did not happen.
            state.currentMode = mode
            state.notice = "Changing to \(mode.label)…"
            Task.detached { [weak self] in
                let ok = Win32SystemInfo.setDisplayMode(mode)
                let now = Win32SystemInfo.currentDisplayMode()
                await MainActor.run {
                    self?.add(.notice(ok ? nil
                        : "The display refused \(mode.label)."))
                    if let now { self?.state.currentMode = now }
                }
            }

        case .openNetworkSettings:
            Task.detached { Win32Adapters.openWindowsSettings() }

        case .pickWallpaper:
            Task.detached { [weak self] in
                guard let path = Win32Dialog.openImage() else { return }
                let ok = Win32SystemInfo.setWallpaper(path)
                let now = Win32SystemInfo.wallpaper()
                await MainActor.run {
                    self?.state.wallpaper = now
                    self?.add(.notice(ok ? nil : "Could not set that wallpaper."))
                }
            }
        }
    }

    /// One pass, off the UI thread, for every pane at once.
    ///
    /// Not per-pane: the whole set is a few hundred milliseconds and switching
    /// panes should be instant. The one thing deliberately NOT re-read on a
    /// refresh is anything that would ask the monitor over DDC/CI more often
    /// than a person changes it.
    private func _load() {
        Task.detached { [weak self] in
            let machine = Win32SystemInfo.machine()
            let modes = Win32SystemInfo.displayModes()
            let current = Win32SystemInfo.currentDisplayMode()
            let brightness = Win32Status.brightness()
            let volume = Win32Status.volume()
            let dark = Win32Control.isDarkMode
            let drives = Win32SystemInfo.drives()
            let wallpaper = Win32SystemInfo.wallpaper()
            let adapters = Win32Adapters.all()
            await MainActor.run {
                self?.add(.loaded(machine: machine, modes: modes,
                                  current: current, brightness: brightness,
                                  volume: volume, dark: dark, drives: drives,
                                  wallpaper: wallpaper, adapters: adapters))
            }
        }
    }
}

let settingsBloc = SettingsBloc()
#endif
