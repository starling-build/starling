// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Shared plumbing for the example apps ported from famous Flutter samples:
// the engine-data bootstrap and the window-host run sequence, so each port's
// main.swift stays as close as possible to its Dart original's
// `void main() => runApp(MyApp());`.

#if os(Linux)
import CupertinoIcons
import Flutter
import FlutterGTK
import FlutterSwiftBridge
import Foundation
import Glibc

/// Dev bootstrap: when `<exe dir>/data` is missing (a `swift run` from the
/// repo rather than an installed bundle), assemble it as symlinks. This was
/// one of several hand-maintained copies of the candidate list, and it had
/// drifted — it knew about a bundle's `engine/share/icudtl.dat` but linked
/// assets only from `Resources/`, which a bundle does not ship, so an example
/// run from an unpacked SDK came up with no fonts. The list lives in the host
/// now, which is the thing that starts the engine.
public func ensureEngineData() {
    GTKHost.ensureEngineData()
}

/// The host created by runExampleApp, for apps that need window control
/// beyond mounting a widget (e.g. the YouTube example's fullscreen toggle).
public private(set) var activeGTKHost: GTKHost? = nil

/// Opens a window on the desktop session (GTK embedder, engine in Swift
/// mode), mounts the app widget, and runs until the window closes.
public func runExampleApp(
    title: String, width: Int = 480, height: Int = 720, root: () -> Widget
) {
    setbuf(stdout, nil)
    print("[\(title)] Starting (GTK host)")
    ensureEngineData()
    guard let host = GTKHost(width: width, height: height, title: title) else {
        fatalError("""
        [\(title)] Could not create a window — run inside a Wayland or X11 \
        session (WAYLAND_DISPLAY/DISPLAY set).
        """)
    }
    activeGTKHost = host
    host.mountWidget(root)
    host.run()
}
#endif
