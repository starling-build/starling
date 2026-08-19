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
    /// Whether pure black in the tree is a hole rather than a colour.
    ///
    /// A dock is a slab floating over the wallpaper, so its window is the
    /// full strip and most of that has to disappear; a menu bar fills its
    /// strip and does not want this. The engine's swap chain is opaque, so
    /// this is a colour key rather than per-pixel alpha — which is why it
    /// costs the ability to paint true black here. Every Starling surface is
    /// a near-black, so nothing real is lost.
    public let transparent: Bool
    /// Extra points the WINDOW occupies beyond the strip it reserves,
    /// extending in from the edge.
    ///
    /// A dock needs this to draw above itself — a hover label, a right-click
    /// menu — because a window is a hard clip and anything taller than the
    /// strip would be cut off. The overhang reserves nothing, is transparent,
    /// and is click-through until something paints in it.
    public let overhang: Int

    public init(edge: PanelEdge, thickness: Int, monitor: Int? = nil,
                reserveSpace: Bool = false, takesFocus: Bool = false,
                transparent: Bool = false, overhang: Int = 0) {
        self.edge = edge
        self.thickness = thickness
        self.monitor = monitor
        self.reserveSpace = reserveSpace
        self.takesFocus = takesFocus
        self.transparent = transparent
        self.overhang = overhang
    }
}

/// Where an overlay sits: the whole screen, or a floating panel. Handed to `Win32WindowedHost.overlay`
/// before `runStarlingApp`, for the same reason `PanelPlacement` is: the
/// window it restyles does not exist until the host boots, and a tree laid
/// out against the pre-restyle size renders its first frame at the wrong
/// geometry.
public struct OverlayPlacement: Sendable {
    /// Index into `Win32Display.monitors()`, or nil for the primary.
    public let monitor: Int?
    /// The whole surface's opacity. Uniform rather than per-pixel — the
    /// engine's swap chain is opaque — which is what gives the frosted-panel
    /// look without a blur we have no cheap way to do.
    public let opacity: Double
    /// The panel's size in POINTS, or nil to cover the whole monitor.
    ///
    /// Windows' own Start menu is a floating panel rather than a takeover, and
    /// a launcher that blacks out the screen to show twelve icons is the
    /// macOS habit imported without the macOS reason for it.
    public let size: (width: Double, height: Double)?
    /// Points between the panel's bottom edge and the bottom of the work
    /// area. The work area already excludes the dock.
    public let bottomMargin: Double

    public init(monitor: Int? = nil, opacity: Double = 0.96,
                size: (width: Double, height: Double)? = nil,
                bottomMargin: Double = 12) {
        self.monitor = monitor
        self.opacity = opacity
        self.size = size
        self.bottomMargin = bottomMargin
    }
}

/// Toggling a surface that lives in another process.
///
/// The framework mounts one widget root per process and the Win32 host owns
/// one window, so Starling's surfaces on Windows are separate processes — the
/// bar, the dock, the launcher. A registered window message broadcast is the
/// documented way for unrelated processes to talk with no socket and no pipe:
/// every process that registers the same string gets the same id back.
public enum Win32Shell {
    /// Asks every Starling overlay in the session to show or hide itself.
    public static func toggleOverlay() {
        flwin32_shell_broadcast_toggle()
    }

    /// Opens Starling's own Settings window.
    ///
    /// Another run of this binary, like the launcher: the framework mounts one
    /// widget root per process, so a second surface is a second process. It is
    /// found by asking for THIS executable rather than a recorded path — the
    /// shell may be running from a staging tree, a package, or a build
    /// directory, and only one of those is ever right.
    ///
    /// Already open? Windows brings the existing window forward rather than
    /// this making a second one — see `flwin32_shell_open_settings`.
    public static func openSettings() {
        flwin32_shell_open_settings()
    }

    /// Explorer's own taskbar — hidden, so that Starling's bar and dock are
    /// the only shell chrome on the screen rather than a second set beside
    /// Windows'.
    ///
    /// This is not "replacing the shell": explorer.exe keeps running, keeps
    /// owning the desktop and the tray plumbing and every shell dialog, and
    /// its taskbar comes back on request. Swapping `Winlogon\Shell` is the
    /// real replacement and a much later phase — it takes the desktop with
    /// it, so a crash leaves the user with nothing.
    ///
    /// Idempotent, and worth re-asserting on a timer: explorer puts its
    /// taskbar back on a display change and whenever it restarts.
    @discardableResult
    public static func hideNativeTaskbar() -> Bool {
        flwin32_explorer_taskbar_hide() != 0
    }

    /// Puts it back, with the appbar state the user had before the first
    /// hide. Runs from `atexit` on the ordinary exit path too — a machine
    /// left with no taskbar and no Starling cannot be recovered from the
    /// desktop, so this must not depend on the shell shutting down tidily.
    @discardableResult
    public static func showNativeTaskbar() -> Bool {
        flwin32_explorer_taskbar_show() != 0
    }

    public static var nativeTaskbarIsVisible: Bool {
        flwin32_explorer_taskbar_visible() != 0
    }
}
#endif
