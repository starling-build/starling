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
            ensureEngineData()
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

    /// Engine data (icudtl.dat + flutter_assets) for standalone runs: make
    /// a `data/` beside the executable pointing at an engine checkout. The
    /// desktop's staged tree ships these; a `swift run` build has neither.
    private static func ensureEngineData() {
        let fm = FileManager.default
        guard let exe = try? fm.destinationOfSymbolicLink(atPath: "/proc/self/exe")
        else { return }
        let dataDir = (exe as NSString).deletingLastPathComponent + "/data"
        if fm.fileExists(atPath: dataDir + "/icudtl.dat") { return }

        let env = ProcessInfo.processInfo.environment
        var icuCandidates: [String] = []
        for key in ["FLUTTER_SWIFT_ENGINE_OUT", "FLUTTER_ENGINE_OUT"] {
            if let v = env[key], !v.isEmpty { icuCandidates.append(v + "/icudtl.dat") }
        }
        // …/sdk/Sources/FlutterGTK/GTKWindowedHost.swift → sdk/
        let sdkDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().path
        icuCandidates += [
            // The starling repo's engine symlink, one level above sdk/.
            sdkDir + "/../engine/src/out/host_debug/icudtl.dat",
        ]
        guard let icu = icuCandidates.first(where: { fm.fileExists(atPath: $0) })
        else {
            FileHandle.standardError.write(Data((
                "[GTKWindowedHost] no data/ next to the executable and no "
                + "engine checkout to link from — tried "
                + icuCandidates.joined(separator: ", ") + "\n").utf8))
            return
        }
        try? fm.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: dataDir + "/icudtl.dat",
                                   withDestinationPath: icu)
        let assets = sdkDir + "/Resources/flutter_assets"
        if fm.fileExists(atPath: assets) {
            try? fm.createSymbolicLink(atPath: dataDir + "/flutter_assets",
                                       withDestinationPath: assets)
        }
    }
}
