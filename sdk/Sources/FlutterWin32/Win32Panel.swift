// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Shell chrome on Windows: a window that behaves like a bar or a dock rather
// than like an application.
//
// Starling on Linux composites its own chrome because it IS the compositor.
// Windows has no such seat — DWM owns compositing and is not replaceable — so
// a Starling shell here is chrome plus a window manager: we draw the bar in an
// undecorated always-on-top window and move everyone else's windows with
// user32. This file is the first half of that.

#if os(Windows)
import FlutterWin32Bridge

/// Which screen edge a panel is pinned to.
public enum PanelEdge: Int32 {
    case top = 0
    case bottom = 1
    case left = 2
    case right = 3
}

/// One monitor, in the virtual-desktop coordinate space Windows lays screens
/// out in — so `x`/`y` may be negative for a screen left of or above the
/// primary, exactly like Starling's own DisplayLayout.
public struct Win32Monitor: Sendable {
    public let index: Int
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let isPrimary: Bool
}

public enum Win32Display {

    /// Every monitor, primary first-ish (Windows does not promise an order —
    /// read `isPrimary`, never index 0).
    public static func monitors() -> [Win32Monitor] {
        let n = Int(flwin32_monitor_count())
        var out: [Win32Monitor] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            var x: Int32 = 0, y: Int32 = 0, w: Int32 = 0, h: Int32 = 0
            var primary: Int32 = 0
            guard flwin32_monitor_rect(Int32(i), &x, &y, &w, &h, &primary) != 0
            else { continue }
            out.append(Win32Monitor(index: i, x: Int(x), y: Int(y),
                                    width: Int(w), height: Int(h),
                                    isPrimary: primary != 0))
        }
        return out
    }

    public static func primary() -> Win32Monitor? {
        let all = monitors()
        return all.first(where: { $0.isPrimary }) ?? all.first
    }
}

/// Where a panel sits. Handed to `Win32WindowedHost.panel` before
/// `runStarlingApp`, because the window it restyles does not exist until the
/// host boots.
public struct PanelPlacement: Sendable {
    public let edge: PanelEdge
    /// Physical pixels. The engine applies the monitor's scale to the widget
    /// tree inside, so a 40pt bar on a 200% display asks for 80 here.
    public let thickness: Int
    /// Index into `Win32Display.monitors()`, or nil for the primary.
    public let monitor: Int?
    /// Ask Windows to RESERVE the strip (register as an appbar), so maximized
    /// windows stop at the bar instead of going under it. Without this the
    /// panel is only an overlay — which is the right answer for a HUD and the
    /// wrong one for shell chrome.
    public let reserveSpace: Bool

    public init(edge: PanelEdge, thickness: Int, monitor: Int? = nil,
                reserveSpace: Bool = false) {
        self.edge = edge
        self.thickness = thickness
        self.monitor = monitor
        self.reserveSpace = reserveSpace
    }
}
#endif
