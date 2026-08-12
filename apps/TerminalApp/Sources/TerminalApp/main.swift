// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Host-neutral entry (runStarlingApp), the same shape TaskManagerApp uses:
// spawned by the shell it composites as a DMA-BUF child; built with
// STARLING_APP_GTK=1 it also runs windowed on an ordinary desktop session
// through the engine's GTK embedder. The GTK import is compiled out of the
// shipped build, so its link set is unchanged.

import Flutter
import FlutterSwiftBridge
import Foundation

#if os(Windows)
import FlutterWin32
#elseif os(macOS)
import FlutterCocoa
#elseif STARLING_GTK
import FlutterGTK
#endif

// Must run before runStarlingApp: these fill in the windowed-host hooks that
// the host-neutral entry looks for when there is no shell socket. Neither
// Windows nor macOS has a Starling shell to be a child of — the compositor is
// Linux-only — so both always open their own window; on Linux the GTK host is
// the opt-in benchmark/dev build and the default binary still composites
// through the shell.
#if os(Windows)
Win32WindowedHost.install()
#elseif os(macOS)
CocoaWindowedHost.install()
#elseif STARLING_GTK
GTKWindowedHost.install()
#endif

// Window size for windowed hosts only — the shell sizes the DMA-BUF child
// itself, so these are ignored there. Overridable because matching another
// terminal's grid cell-for-cell is the only way to benchmark the two fairly.
#if os(Windows)
private let defaultWindowW = 900
private let defaultWindowH = 600
#else
private let defaultWindowW = 1100
private let defaultWindowH = 700
#endif

private func windowMetric(_ key: String, _ fallback: Int) -> Int {
    guard let v = ProcessInfo.processInfo.environment[key], let n = Int(v), n > 0
    else { return fallback }
    return n
}

runStarlingApp(title: "Terminal",
               width: windowMetric("STARLING_WINDOW_W", defaultWindowW),
               height: windowMetric("STARLING_WINDOW_H", defaultWindowH)) {
    MacosApp(
        theme: MacosThemeData.dark(),
        home: TerminalApp()
    )
}
