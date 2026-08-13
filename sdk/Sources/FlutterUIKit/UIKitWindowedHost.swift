// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The iOS side of runStarlingApp: linking FlutterUIKit and calling install()
// gives the host-neutral entry a backend, so the same widget tree that runs
// as a Starling desktop child on Linux runs as an app on iOS with no change
// at the call site. The counterpart of CocoaWindowedHost, GTKWindowedHost and
// Win32WindowedHost.
//
// There is no shell socket to be a child of here — Starling's compositor is
// Linux-only — so this is the only backend runStarlingApp can pick on iOS.
//
// The requested width and height are dropped, and that is not an oversight:
// iOS gives an app the screen and nothing else, so a size passed in has
// nowhere to go. Anything that needs the real one reads
// UIKitHost.windowSize after the tree is mounted, or — better — asks the
// widget tree, which learns it from the engine's viewport metrics like any
// other Flutter app.

#if os(iOS)
import Flutter
import FlutterSwiftBridge
import Foundation

public enum UIKitWindowedHost {

    /// The running host, kept so it outlives install()'s closures.
    nonisolated(unsafe) private static var host: UIKitHost? = nil

    /// Point runStarlingApp at the UIKit host. Call once, before
    /// runStarlingApp.
    public static func install() {
        windowedHostBoot = { title, _, _, root in
            setbuf(stdout, nil)
            print("[\(title)] Starting (UIKit host)")
            let h = UIKitHost(builder: root)
            host = h
            h.run(title: title)
        }
        // hostPeriodicTimerInstall is deliberately left unset, for the same
        // reason as the Cocoa host: on Darwin libdispatch drives the main
        // queue from the main run loop, so a DispatchSourceTimer on .main
        // already fires on the thread UIKit runs the UI on. Only the GTK host
        // needs its own, because gtk_main does not pump GCD.
    }
}
#endif
