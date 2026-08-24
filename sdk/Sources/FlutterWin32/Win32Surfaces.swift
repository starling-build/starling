// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Surface views, the Swift half of flwin32_surface.c: the one-app shell
// exploration (branch winshell-oneapp). One process — the dock's — owns the
// desktop (wallpaper + icon grid) and the launcher as ENGINE VIEWS instead
// of spawning a process per surface, riding the same multi-view path the
// popup surfaces proved: a builder per view id, a tree per view, input
// tagged with the view it landed in.
//
// The registry is Win32PopupSurfaces' own (one multiViewContentBuilder per
// process, so one builder table), which is also what routes each view's
// first composite here: the desktop surface shows itself only once its
// first scene is on the swapchain — never an empty first paint.
//
// What this changes about overlay life, and why it is simpler here: a
// hidden engine view still composites (popups depend on that), so the
// launcher's tree mounts at process start while its window is hidden — no
// full-size parks, no same-size WM_SIZE kicks, no preload dance. The first
// toggle is ShowWindow on a window whose content is already current.

#if os(Windows)
import Flutter
import FlutterSwiftBridge
import FlutterWin32Bridge
import Foundation

public enum Win32SurfaceKind {
    /// The whole monitor, pinned to the bottom of the z-order; shows itself
    /// on its view's first composite.
    case desktop
    /// A sized panel centred at the bottom of the work area (the launcher's
    /// geometry): created hidden, activatable, rounded, dismissing on
    /// deactivate, answering the launcher toggle broadcast.
    case overlay
    /// An ordinary application window owned by the shell's process:
    /// resizable, in the taskbar, drawing its own caption, and CLOSING TO
    /// HIDDEN so the next open is a ShowWindow on a tree that is already
    /// composited. This is what makes an app cost no engine startup — the
    /// ~110 ms of ANGLE bringing up a D3D device is charged once per
    /// PROCESS, and a view on a running engine pays none of it.
    case app
}

public enum Win32Surfaces {

    nonisolated(unsafe) private static var kinds: [Int: Win32SurfaceKind] = [:]
    nonisolated(unsafe) private static var toggleHandlers:
        [Int: (Bool) -> Void] = [:]
    nonisolated(unsafe) private static var closeHandlers: [Int: () -> Void] = [:]
    nonisolated(unsafe) private static var installed = false

    private static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        // Overlay visibility changes arrive from the window's own procedure
        // (the toggle broadcast, a click-away WA_INACTIVE) on the UI thread.
        flwin32_surface_on_overlay_toggled({ _, viewId, visible in
            Win32Surfaces.toggleHandlers[Int(viewId)]?(visible != 0)
        }, nil)
        // An app surface's close button hides it; the tree gets to reset.
        flwin32_surface_on_app_closed({ _, viewId in
            Win32Surfaces.closeHandlers[Int(viewId)]?()
        }, nil)
    }

    /// Opens a surface view on the host's monitor and registers its content.
    /// The builder receives the view id, so a tree that needs its surface
    /// (the launcher asking "am I visible?") can hold it. Width/height/
    /// bottomMargin are LOGICAL POINTS and only meaningful for `.overlay`.
    /// Returns the view id, or nil when the surface could not be created.
    public static func open(kind: Win32SurfaceKind,
                            width: Double = 0, height: Double = 0,
                            bottomMargin: Double = 0,
                            content: @escaping (Int) -> Widget) -> Int? {
        guard let host = Win32WindowedHost.host else { return nil }
        Win32PopupSurfaces.installIfNeeded()
        installIfNeeded()
        // 0 = DESKTOP, 1 = OVERLAY, 2 = APP.
        let cKind: Int32 = switch kind {
        case .desktop: 0
        case .overlay: 1
        case .app:     2
        }
        let id = flwin32_surface_open(host.cHost, cKind, width, height, bottomMargin)
        guard id > 0 else { return nil }
        kinds[Int(id)] = kind
        Win32PopupSurfaces.builders[Int(id)] = { content(Int(id)) }
        // Opening is not itself a build; kick the engine so the adapter
        // mounts the new view's tree on the next frame.
        hostScheduleEngineFrame?()
        return Int(id)
    }

    /// Called from the shared first-composite hook for EVERY new view; acts
    /// only on surface ids. The desktop shows itself here — its window
    /// reaches the screen already painted. An app surface does NOT: it is
    /// built hidden at startup and shown when the user asks for it, which is
    /// the whole point (the tree is already composited by then).
    static func handleFirstComposite(_ id: Int) {
        guard kinds[id] == .desktop, let host = Win32WindowedHost.host else {
            return
        }
        flwin32_surface_show(host.cHost, Int64(id))
    }

    /// Called when an app surface's close button hid it.
    public static func onClose(_ id: Int, _ handler: @escaping () -> Void) {
        closeHandlers[id] = handler
    }

    /// Show and raise an app surface — the "open" gesture once its tree is
    /// already built.
    public static func show(_ id: Int) {
        guard let host = Win32WindowedHost.host else { return }
        // FORCE ONE COMPOSITE, or the window opens blank.
        //
        // The adapter composites a SECONDARY view only when that view's own
        // pipeline has layout or paint work, on purpose: a static second
        // monitor should not re-present on every animation frame of the
        // first. A window that has merely become visible has no such work —
        // its tree is exactly as it was — so the frame the show schedules
        // paints every other view and skips this one, and the window keeps
        // whatever it last presented while hidden. For the file explorer,
        // built at startup, that is the empty page it had before its first
        // listing arrived: measured, a window shown this way stays white
        // until something resizes it.
        //
        // Both halves are needed. This flag makes the next frame composite
        // the view; `hostScheduleEngineFrame` is what makes a next frame
        // happen at all on Windows, where the bridge's own `scheduleFrame`
        // never produces one.
        _forceNextComposite = true
        flwin32_surface_show(host.cHost, Int64(id))
        hostScheduleEngineFrame?()
    }

    /// The overlay's visibility changes, with the NEW visibility — richer
    /// than the host onToggle contract (which made the tree ask), because
    /// the C side already knows.
    public static func onToggle(_ id: Int,
                                _ handler: @escaping (Bool) -> Void) {
        toggleHandlers[id] = handler
    }

    /// Where this surface's client area sits inside the HOST window's client
    /// space, in logical points — what a tree hosted here must add to any
    /// geometry it hands to the popup surfaces, whose coordinates are the
    /// host window's. Zero when the id is not a surface, so a caller that
    /// may or may not be hosted can add it unconditionally.
    public static func clientOffset(_ id: Int) -> (x: Double, y: Double) {
        guard let host = Win32WindowedHost.host else { return (0, 0) }
        var x = 0.0
        var y = 0.0
        flwin32_surface_client_offset(host.cHost, Int64(id), &x, &y)
        return (x, y)
    }

    public static func isVisible(_ id: Int) -> Bool {
        guard let host = Win32WindowedHost.host else { return false }
        return flwin32_surface_is_visible(host.cHost, Int64(id)) != 0
    }

    public static func setVisible(_ id: Int, _ visible: Bool) {
        guard let host = Win32WindowedHost.host else { return }
        flwin32_surface_set_visible(host.cHost, Int64(id), visible ? 1 : 0)
    }

    public static func close(_ id: Int) {
        guard let host = Win32WindowedHost.host else { return }
        kinds.removeValue(forKey: id)
        toggleHandlers.removeValue(forKey: id)
        Win32PopupSurfaces.builders.removeValue(forKey: id)
        flwin32_surface_close(host.cHost, Int64(id))
    }

    /// The surface window's client area in logical points — what replaces
    /// `host.clientSize` for a tree running as a surface view (the host is
    /// the dock's panel there).
    public static func clientSize(_ id: Int)
        -> (width: Double, height: Double)? {
        guard let host = Win32WindowedHost.host else { return nil }
        var w = 0.0, h = 0.0
        guard flwin32_surface_client_size(host.cHost, Int64(id), &w, &h) != 0
        else { return nil }
        return (w, h)
    }

    /// The surface's top-level window handle, for per-window registrations
    /// (the desktop's OLE drop target).
    public static func windowHandle(_ id: Int) -> UInt64 {
        guard let host = Win32WindowedHost.host else { return 0 }
        return flwin32_surface_window(host.cHost, Int64(id))
    }
}
#endif
