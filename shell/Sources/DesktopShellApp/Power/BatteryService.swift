// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import StarlingPower
#if os(Linux)
import CUdev
#endif

/// Owns the shell's battery picture. Reads land in `snapshot` on the main
/// thread and `onChange` fires there — but only when something actually
/// changed, so nothing repaints unless the reading moved.
///
/// It is TOLD, not asked. The kernel emits a `power_supply` uevent whenever a
/// supply changes — plug, unplug, capacity step — and that is what triggers a
/// read. The five-second poll this replaces was, by the end, the single most
/// expensive thing an idle desktop did: reading an AC adapter's `online`
/// makes the kernel interpret the ACPI method behind it, so a `perf` profile
/// of a desktop doing nothing was dominated by AML parsing.
///
/// If the monitor cannot be opened the timer comes back. Better a heartbeat
/// than a battery icon that never moves again.
final class BatteryService {

    /// Main-thread only, like all shell state.
    private(set) var snapshot = BatteryStatus()
    var onChange: (() -> Void)?

    private let queue = DispatchQueue(label: "starling.shell.battery",
                                      qos: .utility)
    private var timer: DispatchSourceTimer?
    #if os(Linux)
    private var udevHandle: OpaquePointer?
    private var monitor: OpaquePointer?
    private var monitorSource: DispatchSourceRead?
    #endif

    func start() {
        refreshNow()
        #if os(Linux)
        if _startUdevWatch() { return }
        print("[BatteryService] no power_supply monitor; falling back to a poll")
        #endif
        _startPoll()
    }

    private func _startPoll() {
        let t = DispatchSource.makeTimerSource(queue: .global())
        // 5s covers the fastest thing worth showing promptly — the charging
        // bolt after plugging in.
        t.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5))
        t.setEventHandler { [weak self] in self?.refreshNow() }
        t.resume()
        timer = t
    }

    #if os(Linux)
    /// Subscribe to power_supply uevents. False if anything is missing, in
    /// which case the caller polls instead.
    private func _startUdevWatch() -> Bool {
        // A fake supply directory (STARLING_POWER_SUPPLY_DIR, used by the
        // tests and the simulator) produces no kernel events at all, so the
        // poll is the only thing that would ever notice it change.
        if ProcessInfo.processInfo.environment["STARLING_POWER_SUPPLY_DIR"] != nil {
            return false
        }
        guard let u = udev_new() else { return false }
        // "udev", not "kernel": the rebroadcast group is readable by any
        // user, while the kernel group needs CAP_NET_ADMIN — which the dev
        // loop has under sudo and a real session does not.
        guard let m = udev_monitor_new_from_netlink(u, "udev") else {
            udev_unref(u)
            return false
        }
        udev_monitor_filter_add_match_subsystem_devtype(m, "power_supply", nil)
        guard udev_monitor_enable_receiving(m) >= 0 else {
            udev_monitor_unref(m)
            udev_unref(u)
            return false
        }
        let fd = udev_monitor_get_fd(m)
        guard fd >= 0 else {
            udev_monitor_unref(m)
            udev_unref(u)
            return false
        }
        udevHandle = u
        monitor = m
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global())
        let handler: () -> Void = { [weak self] in
            guard let self, let m = self.monitor else { return }
            // Drain every queued device or the fd stays readable and this
            // spins. The devices themselves say nothing we need — the read
            // below is the answer — so they are taken and released.
            while let dev = udev_monitor_receive_device(m) {
                udev_device_unref(dev)
            }
            self.refreshNow()
        }
        src.setEventHandler(
            handler: unsafeBitCast(handler, to: (@Sendable () -> Void).self))
        src.resume()
        monitorSource = src
        return true
    }
    #endif

    /// Re-read sysfs off the main thread — cheap, but a misbehaving driver
    /// can stall a sysfs read, and the compositor must not stall with it.
    func refreshNow() {
        let work: () -> Void = { [weak self] in
            let status = BatteryReader.read()
            let apply: () -> Void = { [weak self] in
                guard let self, self.snapshot != status else { return }
                self.snapshot = status
                self.onChange?()
            }
            onPlatformThread(apply)
        }
        queue.async(execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }
}
