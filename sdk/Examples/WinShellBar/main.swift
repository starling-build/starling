// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Starling shell chrome on Windows — the desktop port's prototype shell.
//
// Phase 0 proved the five things a panel needs from the HOST rather than from
// the UI: an undecorated topmost edge-anchored window (WS_POPUP +
// WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE), monitor geometry, the
// Starling look through the Win32 embedder, a periodic timer reaching the UI
// thread through the message loop, and an appbar reservation so maximized
// windows stop at the strip instead of sliding under it.
//
// Phase 1 is window management, because DWM cannot be replaced: a Starling
// shell on Windows never owns anyone's pixels, it owns their GEOMETRY.
//
// ONE BAR, on the bottom edge. There was a menu bar along the top for a
// while, macOS-shaped, with the dock below it — and that was two strips to
// reach for on a system whose users have one. The dock is the whole of the
// chrome now, and it covers the taskbar it replaces: launcher where Start
// was, running apps in the middle, clock and status at the right. Explorer's
// own taskbar is hidden (`--keep-taskbar` opts out, `--restore-taskbar` puts
// it back and exits); explorer itself keeps running, because it still owns
// the wallpaper, the desktop icons, drag-and-drop and every shell dialog,
// none of which we are ready to take over.
//
// ONE SURFACE PER PROCESS. The Flutter framework mounts a single root and the
// Win32 host owns a single window, so the dock and the launcher are two runs
// of this binary rather than two windows of one — the same shape the Linux
// shell uses for its per-output shells:
//
//   WinShellBar.exe             the dock, bottom edge
//   WinShellBar.exe --launcher  the launcher, hidden until asked for
//   ... --monitor N             put either on a screen other than the primary
//
//   swift build -c release --product WinShellBar

#if os(Windows)
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import FlutterWin32Bridge
import Foundation

Win32WindowedHost.install()

// Diagnostics. `--plain` skips the panel/overlay restyle entirely and comes
// up as an ordinary window; `--no-appbar` keeps the restyle but does not
// reserve the strip. Between them they bisect "the surface came up blank"
// into restyle-vs-reservation without a rebuild.
let wantsPlain = CommandLine.arguments.contains("--plain")
let wantsAppbar = !CommandLine.arguments.contains("--no-appbar")
let wantsLauncher = CommandLine.arguments.contains("--launcher")
let wantsSettings = CommandLine.arguments.contains("--settings")
let wantsFiles = CommandLine.arguments.contains("--files")

// `--monitor N` indexes Win32Display.monitors(); absent means the primary.
// One value, given to BOTH the placement that puts the window on a screen and
// the tree that lays itself out against that screen — see ShellScreen for
// what went wrong when those were decided separately.
let wantsMonitor: Int? = CommandLine.arguments.firstIndex(of: "--monitor")
    .flatMap { i in i + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[i + 1]) : nil }
ShellScreen.use(monitor: wantsMonitor)

// `--restore-taskbar` does nothing else and exits, so it can be run from
// anywhere to recover a machine whose Starling was killed rather than closed
// (atexit covers the tidy path, and nothing covers taskkill /f).
if CommandLine.arguments.contains("--restore-taskbar") {
    Win32Shell.showNativeTaskbar()
    print("[WinShell] Explorer's taskbar restored")
    exit(0)
}

// `--print-status` prints what the status readout reads and exits.
//
// It is the oracle for the control centre: the panel's job is to CHANGE these
// values, and the only way to know a toggle did anything is to ask the system
// again from outside the running shell. This process links the same readers
// the dock does, so there is nothing to reimplement — and the readers
// themselves were checked against the system independently, by pressing the
// keyboard's mute key and pulling the network adapter and watching them
// follow.
if CommandLine.arguments.contains("--print-status") {
    let volume = Win32Status.volume()
    let network = Win32Status.network()
    let power = Win32Status.power()
    print("volume=\(volume.map { String($0.percent) } ?? "n/a")",
          "muted=\(volume.map { String($0.isMuted) } ?? "n/a")",
          "network=\(network.kind) signal=\(network.signal) ssid=\(network.ssid)",
          // Whether the machine HAS Wi-Fi, which is what decides if the status
          // bar draws a signal meter at all.
          "wifiAdapter=\(network.hasWifiAdapter)",
          "battery=\(power.hasBattery) percent=\(power.percent.map(String.init) ?? "n/a")",
          "dark=\(Win32Control.isDarkMode)",
          separator: "  ")
    exit(0)
}

// `--print-machine` prints what the Settings app reports and exits — the
// oracle for that pane, the same bargain `--print-status` makes for the
// control centre: the only honest way to know a readout is right is to ask
// the system from outside the process that draws it.
if CommandLine.arguments.contains("--print-recent") {
    // What Start's Recommended list would show, and why an entry was dropped.
    // The Recent folder is full of shortcuts to shell namespaces and URIs, not
    // only files, so "8 shortcuts, 0 entries" is a real answer and this is how
    // to tell it apart from a reader that is simply broken.
    var folderBuf = [CChar](repeating: 0, count: 1024)
    let fn = folderBuf.withUnsafeMutableBufferPointer {
        flwin32_known_path(7, $0.baseAddress, 1024)
    }
    let folder = fn > 0 ? String(cString: folderBuf) : "<none>"
    print("[recent] folder: \(folder) (n=\(fn))")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
    print("[recent] entries in folder: \(names.count)")
    for name in names.prefix(12) where name.lowercased().hasSuffix(".lnk") {
        let link = Win32Files.join(folder, name)
        var target = [CChar](repeating: 0, count: 1024)
        var args = [CChar](repeating: 0, count: 8)
        var dir = [CChar](repeating: 0, count: 8)
        let ok = target.withUnsafeMutableBufferPointer { t in
            args.withUnsafeMutableBufferPointer { a in
                dir.withUnsafeMutableBufferPointer { w in
                    flwin32_shortcut_info(link, t.baseAddress, 1024,
                                          a.baseAddress, 8, w.baseAddress, 8)
                }
            }
        }
        let path = String(cString: target)
        print("[recent] lnk \(name) -> rc=\(ok) '\(path)' exists=\(FileManager.default.fileExists(atPath: path))")
    }
    for entry in Win32Files.recent(limit: 20) {
        print("[recent] KEPT \(entry.name)  <-  \(entry.path)")
    }
    print("[recent] user: \(Win32Files.userName())")
    exit(0)
}

if CommandLine.arguments.contains("--print-machine") {
    let m = Win32SystemInfo.machine()
    print("os=\(m.osName) build=\(m.osBuild)")
    print("device=\(m.deviceName)")
    print("cpu=\(m.cpuName) cores=\(m.cpuCores)")
    print("ram=\(m.totalRam / 1_048_576)MB available=\(m.availableRam / 1_048_576)MB")
    print("gpu=\(m.gpuName)")
    print("power=\(m.powerScheme)")
    if let mode = Win32SystemInfo.currentDisplayMode() {
        print("display=\(mode.width)x\(mode.height)@\(mode.refresh)")
    }
    let modes = Win32SystemInfo.displayModes()
    print("modes=\(modes.count): "
          + modes.prefix(6).map { "\($0.width)x\($0.height)@\($0.refresh)" }
              .joined(separator: " "))
    for drive in Win32SystemInfo.drives() {
        print("drive \(drive.letter): \(drive.total / 1_073_741_824)GB total, "
              + "\(drive.free / 1_073_741_824)GB free")
    }
    print("wallpaper=\(Win32SystemInfo.wallpaper())")
    for adapter in Win32Adapters.all() {
        print("adapter \(adapter.name) [\(adapter.kind)] up=\(adapter.isUp) "
              + "speed=\(adapter.speedText) ip=\(adapter.ipv4) "
              + "gw=\(adapter.gateway) dns=\(adapter.dns) "
              + "mac=\(adapter.mac) dhcp=\(adapter.usesDHCP)")
    }
    exit(0)
}

// Span the chosen monitor. Reading the geometry rather than assuming 1920 is
// the point — a panel sized to the wrong screen is the first thing that goes
// wrong on a laptop plus an external.
let screen = ShellScreen.monitor
// PHYSICAL pixels, not logical.
//
// runStarlingApp's size becomes the window's client size in pixels, and the
// engine's view is created for it. The panel restyle then resizes the window
// to the strip — and on a 200% display that is a resize from 1920x44 to
// 3840x88 BEFORE the first frame, which is exactly when the tree has not
// mounted yet. Creating it at the size it is going to be means there is no
// resize to survive. (On the 100% VM the two happened to be equal, which is
// why this never showed up there.)
let panelWidth = Int(screen?.width ?? 1280)
let panelScale = screen?.scale ?? 1.0
print("[WinShell] monitors: \(Win32Display.monitors())")

// takesFocus stays at its default of false for both: clicking a dock icon
// must not take the keyboard off the window the click is about to raise.
if wantsFiles {
    runStarlingApp(title: "Starling Files",
                   width: Int(1040 * panelScale),
                   height: Int(680 * panelScale)) {
        StarlingFiles()
    }
} else if wantsSettings {
    // An ORDINARY WINDOW: no panel, no overlay, no restyle. Settings is an
    // app — it belongs in Alt+Tab, and the user should be able to move and
    // close it like anything else.
    runStarlingApp(title: "Starling Settings",
                   width: Int(980 * panelScale),
                   height: Int(680 * panelScale)) {
        StarlingSettings()
    }
} else if wantsLauncher {
    // An overlay, not a panel: it is not an edge and it reserves nothing. It
    // also comes up HIDDEN — see Launcher.swift for why it runs at all while
    // invisible.
    // --plain: a diagnostic escape hatch. The overlay restyle happens before
    // the tree mounts, so when the launcher comes up blank this is how you
    // find out whether the restyle is what stopped it.
    if !wantsPlain {
        Win32WindowedHost.overlay = OverlayPlacement(
            monitor: wantsMonitor, opacity: 1.0,
            size: (width: kLauncherWidth, height: kLauncherHeight),
            bottomMargin: kLauncherGap)
    }
    // Read the Start Menu and rasterize its icons NOW, off the widget
    // lifecycle: a parked overlay is not sent frames, so its tree does not
    // mount until it is first shown, and everything initState did was landing
    // on the keypress that asked for it. See LauncherPreload.
    launcherBloc.add(.start)
    // PHYSICAL pixels, and the same size the restyle will give it: a window
    // that is not already its final size when the first frame is due does not
    // mount its tree (see flwin32_host.c's parking notes).
    runStarlingApp(title: "Starling Launcher",
                   width: Int(kLauncherWidth * panelScale),
                   height: Int(kLauncherHeight * panelScale)) {
        StarlingLauncher()
    }
} else {
    // Hide Explorer's taskbar BEFORE reserving our own strip: ABM_QUERYPOS
    // moves a new appbar clear of every existing one, so reserving first and
    // hiding second leaves the dock floating a taskbar's height off the
    // bottom of the screen.
    if !keepsNativeTaskbar {
        let hidden = Win32Shell.hideNativeTaskbar()
        print("[WinShell] Explorer taskbar hidden: \(hidden)")
    }
    // transparent: the dock is a slab floating over the wallpaper, so the
    // strip around it has to be a hole rather than a black band. overhang:
    // the window extends above the reserved strip so the hover label and the
    // right-click menu have somewhere to draw — a window is a hard clip, and
    // both are taller than the dock.
    if !wantsPlain {
        // The edge the user last chose, read before the window is made: the
        // tree and the window must agree from the first frame, or the dock
        // draws itself as a column inside a bar-shaped window.
        Win32WindowedHost.panel = PanelPlacement(edge: DockBloc.loadEdge(),
                                                 thickness: kDockHeight,
                                                 monitor: wantsMonitor,
                                                 reserveSpace: wantsAppbar,
                                                 transparent: true,
                                                 overhang: kDockOverhang)
    }
    runStarlingApp(title: "Starling Dock", width: panelWidth,
                   height: Int(Double(kDockHeight + kDockOverhang) * panelScale)) {
        StarlingDock()
    }
}

#else
fatalError("WinShellBar is the Windows shell-chrome prototype.")
#endif
