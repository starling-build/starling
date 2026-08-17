// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import CGtk3
import Flutter
import FlutterSwiftBridge
import Foundation

// The GTK side of runStarlingApp: linking FlutterGTK and calling install()
// gives the host-neutral entry a windowed backend and a GTK-main-loop
// timer. Kept out of FlutterShared on purpose — only apps that want
// standalone windows link GTK at all.

public enum GTKWindowedHost {

    /// The running host, kept so it outlives install()'s closures.
    nonisolated(unsafe) private static var host: GTKHost? = nil

    /// Boxes for g_timeout closures — retained for the app's lifetime,
    /// which is a periodic ticker's lifetime too.
    private final class TimerBox {
        let tick: () -> Void
        init(_ tick: @escaping () -> Void) { self.tick = tick }
    }
    nonisolated(unsafe) private static var timers: [TimerBox] = []

    /// Point runStarlingApp/startPeriodicTimer at GTK. Call once, before
    /// runStarlingApp.
    public static func install() {
        // The system clipboard, so copy/paste reaches the rest of the desktop
        // this window is running on rather than staying inside the process.
        Clipboard.provider = GtkClipboardProvider()
        windowedHostBoot = { title, width, height, root in
            setbuf(stdout, nil)
            print("[\(title)] Starting (GTK host)")
            // Engine data is GTKHost's own business now — it is the thing that
            // starts the engine, and every way in has to arrive with it.
            guard let h = GTKHost(width: width, height: height, title: title) else {
                fatalError("""
                [\(title)] Could not create a window — run inside a Wayland \
                or X11 session (WAYLAND_DISPLAY/DISPLAY set).
                """)
            }
            host = h
            // Benchmark/dev knob: a fullscreen window (no chrome) is the only
            // way to give every terminal in a comparison the same pixel area
            // — width/height requests land wherever each toolkit's decoration
            // and CSD policy put them. GTK queues the request until realize,
            // so setting it before run() is fine.
            if let fs = ProcessInfo.processInfo.environment["STARLING_WINDOW_FULLSCREEN"],
               !fs.isEmpty {
                h.setFullscreen(true)
            }
            h.mountWidget(root)
            h.run()
        }
        hostPeriodicTimerInstall = { seconds, tick in
            // GCD's main queue is not pumped under gtk_main — the tick has
            // to ride the GLib loop, where the framework runs the UI.
            let box = TimerBox(tick)
            timers.append(box)
            let data = Unmanaged.passUnretained(box).toOpaque()
            _ = g_timeout_add(guint(seconds * 1000), { data in
                Unmanaged<TimerBox>.fromOpaque(data!)
                    .takeUnretainedValue().tick()
                return 1  // G_SOURCE_CONTINUE
            }, data)
            return box
        }
    }

}
