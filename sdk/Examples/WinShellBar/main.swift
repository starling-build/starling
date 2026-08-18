// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Starling shell chrome on Windows — Phase 0 of the desktop port.
//
// A status bar pinned to the top of the primary monitor: undecorated, always
// on top, out of Alt+Tab, drawn by the same Flutter tree the Linux shell
// draws. It exists to prove the four things the port depends on before any of
// `shell/` moves, because all four are properties of the HOST, not the UI:
//
//   1. an undecorated, topmost, edge-anchored window at all (WS_POPUP +
//      WS_EX_TOOLWINDOW | WS_EX_TOPMOST — see flwin32_host_set_panel)
//   2. monitor geometry, so the bar spans the screen it is on
//   3. the Starling look rendering correctly through the Win32 embedder
//   4. a live clock, i.e. the periodic timer reaching the UI thread through
//      the Win32 message loop rather than a GTK main context
//
// It also registers as an appbar, so Windows RESERVES the strip and maximized
// windows stop below it rather than sliding underneath — the fifth thing this
// has to prove, and the one that separates shell chrome from an overlay.
//
//   swift build -c release --product WinShellBar

#if os(Windows)
// MacosIcon, not Icon: the desktop is macOS-shaped by standing direction
// (see the shell's CLAUDE.md), and the shell's own status bar uses it.
import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import FlutterWin32
import Foundation

/// Bar height in physical pixels. The VM this is tested on runs 1280x800 at
/// 100%, so physical and logical coincide there; on a 200% display this wants
/// doubling, which is the DPI work Phase 1 has to do properly.
let kBarHeight = 44

final class StarlingBar: StatefulWidget {
    override func createState() -> State<StatefulWidget> { StarlingBarState() }
}

final class StarlingBarState: State<StatefulWidget> {
    private var now = Date()
    private var timer: AnyObject?

    override func initState() {
        super.initState()
        // Through hostPeriodicTimerInstall rather than Foundation.Timer: on
        // the DRM embedder a Foundation timer never fires at all (see the
        // desktop's CLAUDE.md), and going through the host keeps every
        // backend honest about which loop the UI thread is really running.
        timer = startPeriodicTimer(seconds: 1.0) { [weak self] in
            guard let self else { return }
            setState { self.now = Date() }
        }
    }

    private func clockText() -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm  EEE d MMM"
        return f.string(from: now)
    }

    override func build(_ context: any BuildContext) -> Widget {
        // The desktop's own menu-bar palette: near-black with a hairline
        // under it, so it reads as chrome against any wallpaper.
        // Directionality is an inherited widget and has no trailing-closure
        // overload — the ported `child:` spelling is the only one for it.
        return Directionality(
            textDirection: .ltr,
            child: ColoredBox(color: Color(0xF01B1D22)) {
                Padding(padding: EdgeInsets(left: 14, top: 0, right: 14, bottom: 0)) {
                    Row(mainAxisAlignment: .spaceBetween,
                        crossAxisAlignment: .center) {
                        Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 8) {
                            MacosIcon(icon: CupertinoIcons.sparkles, color: Color(0xFF7FB0FF), size: 16)
                            Text("Starling",
                                 style: TextStyle(color: Color(0xFFFFFFFF),
                                                  fontSize: 13,
                                                  fontWeight: .w600))
                            Text("Shell",
                                 style: TextStyle(color: Color(0xFF9AA3B2), fontSize: 13))
                        }
                        Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 12) {
                            MacosIcon(icon: CupertinoIcons.wifi, color: Color(0xFFD5DAE3), size: 15)
                            MacosIcon(icon: CupertinoIcons.battery_full, color: Color(0xFFD5DAE3), size: 17)
                            Text(clockText(),
                                 style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 13))
                        }
                    }
                }
            })
    }
}

Win32WindowedHost.install()

// Span the primary monitor. Reading the geometry rather than assuming 1920
// is the point of item 2 above — and a bar sized to the wrong screen is the
// first thing that goes wrong on a laptop plus an external.
let screen = Win32Display.primary()
let barWidth = screen?.width ?? 1280
print("[WinShellBar] monitors: \(Win32Display.monitors())")

Win32WindowedHost.panel = PanelPlacement(edge: .top, thickness: kBarHeight,
                                         reserveSpace: true)
runStarlingApp(title: "Starling Bar", width: barWidth, height: kBarHeight) {
    StarlingBar()
}

#else
fatalError("WinShellBar is the Windows shell-chrome prototype.")
#endif
