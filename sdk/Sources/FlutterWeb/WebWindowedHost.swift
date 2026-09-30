// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The web's answer to `runStarlingApp`: what CocoaWindowedHost is on macOS.
// An app's main says `WebWindowedHost.install()` and then runs as it does
// everywhere; the "window" is the page's canvas, the title is the tab's.

import CSkwasm
import Flutter
import FlutterSwiftBridge
import FlutterSwiftBridgeCxx

public enum WebWindowedHost {
    public static func install() {
        windowedHostBoot = { title, width, height, root in
            print("[\(title)] Starting (web host)")
            setTitle(title)
            hostSetWindowTitle = setTitle
            WebHost.shared.mountWidget(root)
        }
        hostPeriodicTimerInstall = { seconds, tick in
            RepeatingTimer(seconds: seconds, tick)
        }
    }

    /// A timer that fires until its token is released or stopped.
    final class RepeatingTimer {
        private var stopped = false
        init(seconds: Double, _ tick: @escaping () -> Void) {
            func arm() {
                WebTimers.schedule(afterMilliseconds: seconds * 1000) { [weak self] in
                    guard let self, !self.stopped else { return }
                    tick()
                    arm()
                }
            }
            arm()
        }
        deinit { stopped = true }
        func stop() { stopped = true }
    }

    private static func setTitle(_ title: String) {
        var title = title
        title.withUTF8 { starling_host_set_title($0.baseAddress, UInt32($0.count)) }
    }
}
