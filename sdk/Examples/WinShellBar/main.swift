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
//
//   swift build -c release --product WinShellBar

#if os(Windows)
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import Foundation

Win32WindowedHost.install()

// Diagnostics. `--plain` skips the panel/overlay restyle entirely and comes
// up as an ordinary window; `--no-appbar` keeps the restyle but does not
// reserve the strip. Between them they bisect "the surface came up blank"
// into restyle-vs-reservation without a rebuild.
let wantsPlain = CommandLine.arguments.contains("--plain")
let wantsAppbar = !CommandLine.arguments.contains("--no-appbar")
let wantsLauncher = CommandLine.arguments.contains("--launcher")

// `--restore-taskbar` does nothing else and exits, so it can be run from
// anywhere to recover a machine whose Starling was killed rather than closed
// (atexit covers the tidy path, and nothing covers taskkill /f).
if CommandLine.arguments.contains("--restore-taskbar") {
    Win32Shell.showNativeTaskbar()
    print("[WinShell] Explorer's taskbar restored")
    exit(0)
}

// Span the primary monitor. Reading the geometry rather than assuming 1920
// is the point — a panel sized to the wrong screen is the first thing that
// goes wrong on a laptop plus an external.
let screen = Win32Display.primary()
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
if wantsLauncher {
    // An overlay, not a panel: it is not an edge and it reserves nothing. It
    // also comes up HIDDEN — see Launcher.swift for why it runs at all while
    // invisible.
    // --plain: a diagnostic escape hatch. The overlay restyle happens before
    // the tree mounts, so when the launcher comes up blank this is how you
    // find out whether the restyle is what stopped it.
    if !wantsPlain {
        Win32WindowedHost.overlay = OverlayPlacement(opacity: 0.97)
    }
    runStarlingApp(title: "Starling Launcher",
                   width: Int(screen?.width ?? 1280),
                   height: Int(screen?.height ?? 800)) {
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
        Win32WindowedHost.panel = PanelPlacement(edge: .bottom, thickness: kDockHeight,
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
