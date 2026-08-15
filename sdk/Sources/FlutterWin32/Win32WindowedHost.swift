// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Windows side of runStarlingApp: linking FlutterWin32 and calling
// install() gives the host-neutral entry a windowed backend and a
// message-loop timer. The counterpart of GTKWindowedHost.
//
// Unlike Linux there is no shell socket to be a child of — Starling's
// compositor is Linux-only — so on Windows this is the only backend
// runStarlingApp can pick.

#if os(Windows)
import Flutter
import FlutterSwiftBridge
import FlutterWin32Bridge
import Foundation
import WinSDK

public enum Win32WindowedHost {

    /// The running host, kept so it outlives install()'s closures.
    nonisolated(unsafe) private static var host: Win32Host? = nil

    /// Point runStarlingApp/startPeriodicTimer at the Win32 host. Call once,
    /// before runStarlingApp.
    public static func install() {
        // First, because everything below it may print. A windowed app links
        // GUI-subsystem so Explorer does not open a console window behind it,
        // and this hands the logging back to whoever launched it from a shell.
        // A no-op under Explorer, which is where the silence is wanted.
        flwin32_attach_parent_console()
        // The system clipboard, so copy/paste reaches the rest of Windows
        // rather than staying inside the process.
        Clipboard.provider = Win32ClipboardProvider()
        windowedHostBoot = { title, width, height, root in
            setbuf(stdout, nil)
            print("[\(title)] Starting (Win32 host)")
            ensureEngineData()
            guard let h = Win32Host(width: width, height: height, title: title) else {
                fatalError("""
                [\(title)] Could not create a window or start the engine — \
                check that flutter_engine.dll and flutter_windows.dll are \
                beside the executable.
                """)
            }
            host = h
            h.mountWidget(root)
            h.run()
        }
        hostPeriodicTimerInstall = { seconds, tick in
            // The Win32 host drains GCD's main queue from its message loop
            // (see flwin32_host.c), so unlike the GTK path a plain
            // DispatchQueue timer does reach the thread the framework runs
            // the UI on. Returning nil: DispatchSourceTimer retains itself
            // while active, so there is nothing for the caller to hold.
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + seconds, repeating: seconds)
            timer.setEventHandler(handler: tick)
            timer.resume()
            return timer as AnyObject
        }
    }

    /// Engine data (icudtl.dat + flutter_assets) for standalone runs: make a
    /// `data/` beside the executable pointing at an engine checkout.
    ///
    /// Copies rather than symlinks — a Windows symlink needs Developer Mode
    /// or SeCreateSymbolicLinkPrivilege, so the Linux spelling would fail on
    /// an ordinary account, and silently: the symptom arrives much later as
    /// the engine not finding its data.
    private static func ensureEngineData() {
        let fm = FileManager.default
        guard let exe = ProcessInfo.processInfo.arguments.first else { return }
        let exeDir = URL(fileURLWithPath: exe).deletingLastPathComponent().path
        let dataDir = exeDir + "\\data"
        if fm.fileExists(atPath: dataDir + "\\icudtl.dat") { return }

        let env = ProcessInfo.processInfo.environment
        var icuCandidates: [String] = []
        for key in ["FLUTTER_SWIFT_ENGINE_OUT", "FLUTTER_ENGINE_OUT"] {
            if let v = env[key], !v.isEmpty { icuCandidates.append(v + "/icudtl.dat") }
        }
        // …/sdk/Sources/FlutterWin32/Win32WindowedHost.swift → sdk/
        let sdkDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().path
        icuCandidates += [
            sdkDir + "/../engine/src/out/host_debug/icudtl.dat",
        ]
        guard let icu = icuCandidates.first(where: { fm.fileExists(atPath: $0) })
        else {
            FileHandle.standardError.write(Data((
                "[Win32WindowedHost] no data/ next to the executable and no "
                + "engine checkout to copy from — tried "
                + icuCandidates.joined(separator: ", ") + "\n").utf8))
            return
        }
        try? fm.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        try? fm.copyItem(atPath: icu, toPath: dataDir + "\\icudtl.dat")
        let assets = sdkDir + "/Resources/flutter_assets"
        if fm.fileExists(atPath: assets) {
            try? fm.copyItem(atPath: assets, toPath: dataDir + "\\flutter_assets")
        }
    }
}
#endif
