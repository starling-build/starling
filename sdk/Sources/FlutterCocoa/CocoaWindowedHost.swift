// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The macOS side of runStarlingApp: linking FlutterCocoa and calling install()
// gives the host-neutral entry a windowed backend, so runStarlingApp opens a
// real window on macOS for any app rather than only the samples that drive
// CocoaHost directly. The counterpart of GTKWindowedHost and Win32WindowedHost.
//
// There is no shell socket to be a child of here — Starling's compositor is
// Linux-only — so this is the only backend runStarlingApp can pick on macOS.

#if os(macOS)
import Flutter
import FlutterSwiftBridge
import Foundation

public enum CocoaWindowedHost {

    /// The running host, kept so it outlives install()'s closures.
    nonisolated(unsafe) private static var host: CocoaHost? = nil

    /// Point runStarlingApp at the Cocoa host. Call once, before
    /// runStarlingApp.
    public static func install() {
        windowedHostBoot = { title, width, height, root in
            setbuf(stdout, nil)
            print("[\(title)] Starting (Cocoa host)")
            ensureEngineData()
            guard let h = CocoaHost(width: width, height: height, title: title) else {
                fatalError("""
                [\(title)] Could not start the engine — check that \
                FlutterMacOS.framework and libswift_bridge.dylib are reachable \
                and that data/ beside the executable has flutter_assets and \
                icudtl.dat.
                """)
            }
            host = h
            h.mountWidget(root)
            h.run()
        }
        // hostPeriodicTimerInstall is deliberately left unset. On Darwin
        // libdispatch drives the main queue from the main run loop, so the
        // default DispatchSourceTimer on .main already fires on the thread
        // AppKit runs the UI on — the GTK host only needs its own because
        // gtk_main does not pump GCD.
    }

    /// Engine data (icudtl.dat + flutter_assets) for standalone runs: make a
    /// `data/` beside the executable pointing at an engine checkout or bundle.
    ///
    /// icudtl.dat lives inside FlutterMacOS.framework on this platform
    /// (Versions/A/Resources), rather than beside the engine library as on
    /// Linux, so the framework's own copy is what gets linked.
    private static func ensureEngineData() {
        let fm = FileManager.default
        let dataDir = CocoaHost.executableDirectory + "/data"
        if fm.fileExists(atPath: dataDir + "/icudtl.dat") { return }

        // …/sdk/Sources/FlutterCocoa/CocoaWindowedHost.swift → sdk/
        let sdkDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().path

        var engineDirs: [String] = []
        let env = ProcessInfo.processInfo.environment
        for key in ["FLUTTER_SWIFT_ENGINE_OUT", "FLUTTER_ENGINE_OUT"] {
            if let v = env[key], !v.isEmpty { engineDirs.append(v) }
        }
        engineDirs += [
            sdkDir + "/engine/lib",                              // a bundle
            sdkDir + "/../engine/src/out/host_debug_arm64",
            sdkDir + "/../engine/src/out/host_debug",            // the starling repo's symlink
            sdkDir + "/../starling-engine/engine/src/out/host_debug_arm64",
            sdkDir + "/../starling-engine/engine/src/out/host_debug",
        ]
        // Both spellings: inside the framework is where the engine build puts
        // it, beside the framework is where a hand-assembled tree tends to.
        let icuCandidates = engineDirs.flatMap {
            ["\($0)/FlutterMacOS.framework/Versions/A/Resources/icudtl.dat",
             "\($0)/icudtl.dat"]
        }
        guard let icu = icuCandidates.first(where: { fm.fileExists(atPath: $0) })
        else {
            FileHandle.standardError.write(Data((
                "[CocoaWindowedHost] no data/ next to the executable and no "
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
#endif
