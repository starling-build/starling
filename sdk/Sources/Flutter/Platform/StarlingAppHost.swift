// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

// The host-neutral app entry: the same widget tree runs as a Starling
// desktop child (DMA-BUF compositing, chosen when the shell's socket is in
// the environment) or in an ordinary window (GTK, for standalone dev runs).
// The windowed side stays out of this module — FlutterShared must not drag
// GTK into every desktop app — so it arrives through hooks that
// FlutterGTK's GTKWindowedHost.install() fills in when linked.

/// Boots a window and runs the tree; never returns. Installed by
/// GTKWindowedHost.install() (FlutterGTK). (title, width, height, root).
///
/// `root` escapes. Two of the four hosts build the tree inside the call, but
/// the UIKit one cannot: UIApplicationMain owns the launch sequence, so the
/// engine — and therefore the earliest moment a tree may be mounted — exists
/// only inside a delegate callback that runs after this closure would
/// otherwise have returned. Marking it here rather than having that one host
/// copy the builder into a box keeps the escape visible at the declaration.
public nonisolated(unsafe) var windowedHostBoot:
    ((String, Int, Int, @escaping () -> Widget) -> Void)? = nil

/// Installs a repeating timer on whatever loop the host runs the UI on;
/// returns a token keeping it alive (or nil for hosts that retain it
/// themselves). Installed alongside windowedHostBoot: GCD's main queue is
/// pumped on the DMA-BUF child host but NOT under a GTK main loop, which
/// is why hosts get a say. (seconds, tick).
public nonisolated(unsafe) var hostPeriodicTimerInstall:
    ((Double, @escaping () -> Void) -> AnyObject?)? = nil

/// Asks the host's EMBEDDER for a real engine frame -- the begin-frame /
/// draw-frame pass, through the engine's own scheduler. Installed by hosts
/// where the bridge's programmatic `scheduleFrame` never produces one: on
/// Win32, `PlatformDispatcher.scheduleFrame` reaches
/// `Engine::ScheduleFrame` through the Swift-bridge registry and no frame
/// ever comes back, while the embedder-API path this hook takes
/// (`ForceRedraw` -> `FlutterEngineScheduleFrame`, the same call a resize
/// makes) reliably does. Without it, a `setState` from a
/// `DispatchQueue.main.async` callback -- a shell menu's verbs arriving,
/// a listing finishing its load -- composites only when the next
/// input-driven frame happens along, measured at ~630ms of nothing under
/// a motionless pointer.
public nonisolated(unsafe) var hostScheduleEngineFrame: (() -> Void)? = nil

/// The main entry point for an app that should run under whichever host is
/// available:
/// - `FLUTTER_DMABUF_SOCKET` set (spawned by the Starling shell) — the GPU
///   DMA-BUF child path, exactly `runApp`.
/// - Otherwise, an installed windowed host (GTK — link FlutterGTK and call
///   `GTKWindowedHost.install()` before this).
/// Neither: fail loudly, with the fix in the message.
public func runStarlingApp(title: String, width: Int = 800, height: Int = 600,
                           root: @escaping () -> Widget) {
    #if os(Linux)
    if let sock = ProcessInfo.processInfo.environment["FLUTTER_DMABUF_SOCKET"],
       !sock.isEmpty {
        runApp(root())
        return
    }
    #endif
    if let boot = windowedHostBoot {
        boot(title, width, height, root)
        return
    }
    fatalError("""
    [runStarlingApp] no host: not spawned by the Starling shell \
    (FLUTTER_DMABUF_SOCKET unset) and no windowed host installed — link \
    FlutterGTK and call GTKWindowedHost.install() for standalone windows.
    """)
}

/// A repeating tick on the UI thread, host-appropriate: g_timeout under a
/// GTK main loop, a main-queue DispatchSourceTimer on the child host. Keep
/// the returned token alive for as long as the tick should fire (app-scope
/// tickers can discard it — hosts retain what they must).
/// Token holder — DispatchSourceTimer is a protocol, and the API promises
/// a class instance the caller can retain.
private final class _TimerToken {
    let timer: any DispatchSourceTimer
    init(_ timer: any DispatchSourceTimer) { self.timer = timer }
    deinit { timer.cancel() }
}

@discardableResult
public func startPeriodicTimer(seconds: Double,
                               _ tick: @escaping () -> Void) -> AnyObject? {
    if let install = hostPeriodicTimerInstall {
        return install(seconds, tick)
    }
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + seconds, repeating: seconds)
    timer.setEventHandler(handler: tick)
    timer.resume()
    // App-scope tickers discard the token; keep the source alive anyway.
    let token = _TimerToken(timer)
    _liveTimers.append(token)
    return token
}

private nonisolated(unsafe) var _liveTimers: [AnyObject] = []
