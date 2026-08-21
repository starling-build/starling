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

    /// The running host, kept so it outlives install()'s closures — and
    /// readable, because things a widget tree needs from the host (an icon
    /// texture, the panel geometry) have no other way to reach it. nil until
    /// `runStarlingApp` has built it, which is after the tree's first build
    /// but before its first frame.
    nonisolated(unsafe) public private(set) static var host: Win32Host? = nil

    /// Set before `runStarlingApp` to come up as shell chrome — a bar or a
    /// dock — instead of an ordinary window. It cannot be a parameter of
    /// `runStarlingApp`, which is host-neutral by design and has no business
    /// knowing what a screen edge is.
    nonisolated(unsafe) public static var panel: PanelPlacement? = nil

    /// Set before `runStarlingApp` to come up as a full-screen overlay —
    /// the launcher, Mission Control — hidden until something toggles it.
    /// Mutually exclusive with `panel`; a surface is one or the other.
    nonisolated(unsafe) public static var overlay: OverlayPlacement? = nil

    /// Set before `runStarlingApp` to come up as THE DESKTOP: the full
    /// monitor at the bottom of the z-order (see Win32Host.setDesktop).
    /// `.some(nil)` means the primary monitor. Mutually exclusive with the
    /// other two shapes above.
    nonisolated(unsafe) public static var desktop: Int?? = nil

    /// Point runStarlingApp/startPeriodicTimer at the Win32 host. Call once,
    /// before runStarlingApp.
    public static func install() {
        // First, because everything below it may print. A windowed app links
        // GUI-subsystem so Explorer does not open a console window behind it,
        // and this hands the logging back to whoever launched it from a shell.
        // A no-op under Explorer, which is where the silence is wanted.
        // FIRST, before anything reads the display: until DPI awareness is
        // set the process is told a virtualized screen size, so a shell that
        // asks how wide the monitor is before making a window gets an answer
        // wrong by exactly the scale factor.
        flwin32_process_init()
        flwin32_attach_parent_console()
        flwin32_trace("install(): first Swift code")
        // The system clipboard, so copy/paste reaches the rest of Windows
        // rather than staying inside the process.
        Clipboard.provider = Win32ClipboardProvider()
        windowedHostBoot = { title, width, height, root in
            setbuf(stdout, nil)
            print("[\(title)] Starting (Win32 host)")
            flwin32_trace("runStarlingApp: begin")
            ensureEngineData()
            flwin32_trace("ensureEngineData: done")
            guard let h = Win32Host(width: width, height: height, title: title) else {
                fatalError("""
                [\(title)] Could not create a window or start the engine — \
                check that flutter_engine.dll and flutter_windows.dll are \
                beside the executable.
                """)
            }
            host = h
            // Before the tree mounts: the restyle changes the client size,
            // and a tree laid out against the pre-panel size would render one
            // frame at the wrong geometry.
            if let placement = panel { h.setPanel(placement) }
            if let monitor = desktop { h.setDesktop(monitor: monitor) }
            if let placement = overlay {
                h.setOverlay(monitor: placement.monitor,
                             opacity: placement.opacity,
                             size: placement.size,
                             bottomMargin: placement.bottomMargin,
                             rightMargin: placement.rightMargin,
                             leftMargin: placement.leftMargin,
                             channel: placement.channel,
                             transparent: placement.transparent,
                             passive: placement.passive)
            }
            flwin32_trace("mountWidget: begin")
            h.mountWidget(root)
            flwin32_trace("mountWidget: done")
            h.run()
        }
        // The engine never delivers a frame for the bridge's programmatic
        // scheduleFrame on this embedder; the embedder-API redraw (the same
        // call a resize makes) does. See hostScheduleEngineFrame.
        hostScheduleEngineFrame = { Win32WindowedHost.host?.requestRedraw() }
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
