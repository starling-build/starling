// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Watches NetworkManager for change events via a long-lived `nmcli monitor`
/// child. Every burst of output (connect, disconnect, signal/state changes)
/// coalesces into one `onEvent` call after a short debounce, on a private
/// background queue — the caller re-reads whatever state it cares about and
/// hops to its own main thread.
///
/// If the child dies (NetworkManager restarted, killed), it respawns after a
/// delay until stop() — a desktop session outlives an NM restart. If nmcli is
/// missing, start() is a no-op.
public final class NetworkMonitor: @unchecked Sendable {

    private let queue = DispatchQueue(label: "starling.net.monitor")
    private let onEvent: @Sendable () -> Void
    private var process: Process?
    private var stopped = false
    private var debounce: DispatchWorkItem?

    public init(onEvent: @escaping @Sendable () -> Void) {
        self.onEvent = onEvent
    }

    public func start() {
        queue.async { [self] in
            guard !stopped, process == nil else { return }
            spawn()
        }
    }

    /// Synchronous: a caller that is about to exit() must not race the
    /// child's termination, or `nmcli monitor` is orphaned (it lives in its
    /// own process group, so nothing else ever reaps it).
    public func stop() {
        queue.sync { [self] in
            stopped = true
            debounce?.cancel()
            if let p = process, p.isRunning {
                // SIGKILL, not terminate(): a child inherits the shell's ignored
                // signals, and an ignored SIGTERM left `nmcli monitor` running
                // after every shell exit. It holds nothing worth a clean stop.
                kill(p.processIdentifier, SIGKILL)
            }
            process = nil
        }
    }

    /// Runs on `queue`.
    private func spawn() {
        guard WifiManager.available() else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: WifiManager.nmcli)
        p.arguments = ["monitor"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            // Reading drains the pipe; the content doesn't matter — any
            // monitor line means "something changed, go look".
            guard !handle.availableData.isEmpty else { return }
            self?.eventPending()
        }
        p.terminationHandler = { [weak self] _ in
            guard let self else { return }
            pipe.fileHandleForReading.readabilityHandler = nil
            self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, !self.stopped else { return }
                self.process = nil
                self.spawn()
            }
        }

        do {
            try p.run()
            process = p
        } catch {
            // nmcli exists but won't run — stay quiet; reads elsewhere will
            // report unavailable. No retry loop against a broken binary.
            process = nil
        }
    }

    private func eventPending() {
        queue.async { [self] in
            guard !stopped else { return }
            debounce?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.onEvent() }
            debounce = work
            // One re-read per burst: activation emits a dozen monitor lines
            // in well under a second.
            queue.asyncAfter(deadline: .now() + .milliseconds(400), execute: work)
        }
    }
}
