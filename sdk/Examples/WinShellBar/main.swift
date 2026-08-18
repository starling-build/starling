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
// shell on Windows never owns anyone's pixels, it owns their GEOMETRY. What
// grew on top of that is a shell rather than a demo — a menu bar with a live
// taskbar (Bar.swift) and a dock over the Start Menu's own app catalog
// (Dock.swift).
//
// ONE SURFACE PER PROCESS. The Flutter framework mounts a single root and the
// Win32 host owns a single window, so the bar and the dock are two runs of
// this binary rather than two windows of one — the same shape the Linux shell
// uses for its per-output shells:
//
//   WinShellBar.exe            the menu bar, top edge
//   WinShellBar.exe --dock     the dock, bottom edge
//
//   swift build -c release --product WinShellBar

#if os(Windows)
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import Foundation

Win32WindowedHost.install()

let wantsDock = CommandLine.arguments.contains("--dock")

// Span the primary monitor. Reading the geometry rather than assuming 1920
// is the point — a panel sized to the wrong screen is the first thing that
// goes wrong on a laptop plus an external. Logical, because runStarlingApp's
// size is a client size in points; the panel restyle overrides it a moment
// later with the real edge geometry anyway.
let screen = Win32Display.primary()
let panelWidth = Int(screen?.logicalWidth ?? 1280)
print("[WinShell] monitors: \(Win32Display.monitors())")

// takesFocus stays at its default of false for both: clicking a taskbar
// button or a dock icon must not take the keyboard off the window the click
// is about to raise.
if wantsDock {
    // transparent: the dock is a slab floating over the wallpaper, so the
    // strip around it has to be a hole rather than a black band.
    Win32WindowedHost.panel = PanelPlacement(edge: .bottom, thickness: kDockHeight,
                                             reserveSpace: true, transparent: true)
    runStarlingApp(title: "Starling Dock", width: panelWidth, height: kDockHeight) {
        StarlingDock()
    }
} else {
    Win32WindowedHost.panel = PanelPlacement(edge: .top, thickness: kBarHeight,
                                             reserveSpace: true)
    runStarlingApp(title: "Starling Bar", width: panelWidth, height: kBarHeight) {
        StarlingBar()
    }
}

#else
fatalError("WinShellBar is the Windows shell-chrome prototype.")
#endif
