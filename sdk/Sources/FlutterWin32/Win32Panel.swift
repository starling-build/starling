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
public enum PanelEdge: Int32, Sendable {
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
    /// The display scale: 1.0 at 96 dpi, 2.0 at 192. Windows lets each
    /// monitor have its own, which is why every geometry on this boundary is
    /// in physical pixels and every size the shell asks for is in points.
    public let scale: Double

    /// The monitor in the units a widget tree is laid out in.
    public var logicalWidth: Double { Double(width) / scale }
    public var logicalHeight: Double { Double(height) / scale }
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
            let dpi = flwin32_monitor_dpi(Int32(i))
            out.append(Win32Monitor(index: i, x: Int(x), y: Int(y),
                                    width: Int(w), height: Int(h),
                                    isPrimary: primary != 0,
                                    scale: Double(dpi) / 96.0))
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
    /// LOGICAL POINTS — the same units the widget tree inside is laid out
    /// in, so a 44pt bar is 44pt tall on every display and the host does the
    /// pixel arithmetic. It also re-does it on a scale change, which a
    /// caller working in pixels could not.
    public let thickness: Int
    /// Index into `Win32Display.monitors()`, or nil for the primary.
    public let monitor: Int?
    /// Ask Windows to RESERVE the strip (register as an appbar), so maximized
    /// windows stop at the bar instead of going under it. Without this the
    /// panel is only an overlay — which is the right answer for a HUD and the
    /// wrong one for shell chrome.
    public let reserveSpace: Bool
    /// Whether clicking the panel moves the keyboard to it.
    ///
    /// Default false, and that default is what makes it chrome: a taskbar
    /// that takes focus takes it away from the window the click is about to
    /// raise, so the user's caret leaves the document they were typing in.
    /// Turn it on only for a panel that has a text field of its own — a
    /// launcher, a search bar.
    public let takesFocus: Bool

    public init(edge: PanelEdge, thickness: Int, monitor: Int? = nil,
                reserveSpace: Bool = false, takesFocus: Bool = false) {
        self.edge = edge
        self.thickness = thickness
        self.monitor = monitor
        self.reserveSpace = reserveSpace
        self.takesFocus = takesFocus
    }
}
#endif
