// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import StarlingNet

/// Point-in-time network picture for the status bar icon and popup.
struct NetworkSnapshot {
    /// nmcli exists and at least one managed WiFi radio does too. False is
    /// the "Wi-Fi unavailable" panel, not an error.
    var available = false
    /// The primary wired link, nil when the machine has no managed NIC.
    /// Independent of `available`: a desktop with ethernet and no radio still
    /// has a network panel worth showing.
    var wired: WiredStatus? = nil
    var wifiEnabled = false
    /// Scan results, connected first then by signal (see WifiManager).
    var networks: [WifiNetwork] = []
    var active: WifiConnectionInfo? = nil
    /// Saved profile names — a known network joins without asking again.
    var savedNames: Set<String> = []
    /// The radio new connections go through (the active one, else the first).
    var device = ""
}

/// Owns every nmcli call the shell makes. All child processes run on a
/// private background queue; results land in `snapshot` on the main thread
/// and `onChange` fires there (the shell setStates a rebuild). A NetworkMonitor
/// keeps the snapshot honest while the popup is closed — connect or disconnect
/// from any side (Settings, nmcli in a terminal) updates the bar icon within
/// a second, without the shell polling.
final class NetworkService {

    /// Main-thread only, like all shell state.
    private(set) var snapshot = NetworkSnapshot()
    var onChange: (() -> Void)?

    private let queue = DispatchQueue(label: "starling.shell.network",
                                      qos: .userInitiated)
    private var monitor: NetworkMonitor?
    /// Drops a stale snapshot that finishes after a newer refresh started.
    private var generation = 0

    func start() {
        // The monitor calls back on its own queue; all NetworkService state
        // lives on main. Coerce the main-hop once (codebase idiom) so the
        // monitor's @Sendable callback captures only a @Sendable value.
        let toMain: () -> Void = { [weak self] in self?.refreshNow() }
        let onMain = unsafeBitCast(toMain, to: (@Sendable () -> Void).self)
        let mon = NetworkMonitor { onPlatformThread(onMain) }
        monitor = mon
        mon.start()
        refreshNow()
    }

    /// Re-read state from cached scan results. Cheap (~a few nmcli calls on
    /// the background queue); callable on every popup tick.
    func refreshNow() {
        generation &+= 1
        let gen = generation
        let work: () -> Void = { [weak self] in
            var snap = NetworkSnapshot()
            snap.wired = EthernetManager.status()
            let devices = WifiManager.wifiDevices()
            snap.available = !devices.isEmpty
            if snap.available {
                snap.wifiEnabled = WifiManager.isWifiEnabled()
                if snap.wifiEnabled {
                    snap.networks = WifiManager.listNetworks()
                    snap.active = WifiManager.activeConnectionInfo()
                }
                snap.savedNames = Set(WifiManager.savedConnections())
                snap.device = snap.active?.device ?? devices[0]
            }
            let apply: () -> Void = { [weak self] in
                guard let self, self.generation == gen else { return }
                self.snapshot = snap
                self.onChange?()
            }
            onPlatformThread(apply)
        }
        queue.async(execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }

    /// Ask for a fresh scan and re-read once results have had time to land.
    /// The immediate refresh shows cached results now; the delayed one picks
    /// up whatever the scan found. Called when the popup opens.
    func refreshWithScan() {
        refreshNow()
        let scan: () -> Void = { WifiManager.requestScan() }
        queue.async(execute: unsafeBitCast(scan, to: (@Sendable () -> Void).self))
        let later: () -> Void = { [weak self] in self?.refreshNow() }
        onPlatformThread(after: 3, later)
    }

    /// Join a network. `completion` runs on the main thread with nil on
    /// success or a user-showable error.
    func connect(ssid: String, security: String, password: String?,
                 completion: @escaping (String?) -> Void) {
        let work: () -> Void = { [weak self] in
            // No device pinned here on purpose: WifiManager picks the radio
            // that actually sees this SSID, which is the only choice that
            // holds on a box with more than one WiFi device.
            let err = WifiManager.connect(ssid: ssid, password: password,
                                          security: security)
            let apply: () -> Void = {
                completion(err.map(WifiManager.friendlyConnectError))
                self?.refreshNow()
            }
            onPlatformThread(apply)
        }
        queue.async(execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }

    func disconnect(connectionName: String) {
        runInBackground { WifiManager.disconnect(connectionName: connectionName) }
    }

    func setWiredConnected(_ connected: Bool, device: String) {
        runInBackground {
            connected ? EthernetManager.connect(device: device)
                      : EthernetManager.disconnect(device: device)
        }
    }

    func setWifiEnabled(_ enabled: Bool) {
        // Optimistic: the switch answers the tap now; the refresh that
        // follows the actual radio flip confirms or reverts it.
        snapshot.wifiEnabled = enabled
        onChange?()
        runInBackground { WifiManager.setWifiEnabled(enabled) }
    }

    /// Fire a mutation, then re-read. Errors from these are not surfaced —
    /// the refreshed snapshot IS the outcome (a failed disconnect leaves the
    /// row connected), and the monitor refreshes again when NM settles.
    private func runInBackground(_ op: @escaping () -> String?) {
        let work: () -> Void = { [weak self] in
            _ = op()
            let apply: () -> Void = { self?.refreshNow() }
            onPlatformThread(apply)
        }
        queue.async(execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }
}
