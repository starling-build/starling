// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Popup surfaces, the Swift half: an engine view in its own popup window
// (flwin32_popup.c), with a widget tree of its own built through the
// adapter's multiViewContentBuilder — the multi-view path the Linux
// multi-monitor work built, keyed here by the view id the open returns.
//
// The contract with a caller: register nothing yourself. `open` takes the
// content closure, keys it by the new view id, and the adapter mounts it on
// the next frame (the engine's AddView has already announced the view by
// then — both run on this thread, in that order). Pointer events inside the
// popup arrive in the popup content's own tree, in the popup's local logical
// points; the keyboard never follows, because the popup never takes
// activation — keys keep landing in the host window, which is where menu
// keyboard handling already lives.

#if os(Windows)
import Flutter
import FlutterSwiftBridge
import FlutterWin32Bridge
import Foundation

public enum Win32PopupSurfaces {

    /// Content builders keyed by engine view id. An entry lives exactly as
    /// long as its popup: registered by `open`, removed by `close`.
    nonisolated(unsafe) private static var builders: [Int: () -> Widget] = [:]

    /// Views whose first scene has been composited — the earliest a popup
    /// window may be shown without exposing an unpainted surface.
    nonisolated(unsafe) private static var composited = Set<Int>()

    /// Popups whose owner asked to keep them hidden past the first
    /// composite — a menu that knows more rows are seconds away holds until
    /// `reveal`, so the growth happens off screen and the menu appears once,
    /// at its settled size.
    nonisolated(unsafe) private static var held = Set<Int>()

    nonisolated(unsafe) private static var installed = false

    nonisolated(unsafe) private static var dismissHandler: (() -> Void)?

    /// Wires the adapter's multi-view builder and the C dismissal callback.
    /// Idempotent; `open` calls it, so callers never need to.
    private static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        multiViewContentBuilder = { view in
            // Directionality, unconditionally: this tree has no MacosApp
            // above it, and a bare tree without one must be wrapped (the
            // trap is in CLAUDE.md for a reason).
            let builder = builders[view.viewId]
            if builder == nil {
                // A view with no builder mounts EMPTY, and an empty popup is
                // a black rectangle with dead input — say so, because from
                // the outside the two are indistinguishable.
                try? FileHandle.standardError.write(contentsOf: Data(
                    "[Win32Popup] view \(view.viewId) has no content builder\n".utf8))
            }
            let content: Widget = builder?() ?? SizedBox(width: 0, height: 0)
            return Directionality(textDirection: .ltr, child: content)
        }
        // Popups open HIDDEN and are shown here, after their view's first
        // composite — a window shown at creation spends the frames until
        // its first present as a flat rectangle over whatever it covers.
        // A held popup waits further, for its owner's reveal.
        multiViewFirstComposite = { id in
            composited.insert(id)
            guard !held.contains(id) else { return }
            guard let host = Win32WindowedHost.host else { return }
            flwin32_popup_show(host.cHost, Int64(id))
        }
        flwin32_popup_on_dismiss({ _ in
            Win32PopupSurfaces.dismissHandler?()
        }, nil)
    }

    /// Called when the host window is deactivated, moved or resized while
    /// any popup is open — "the user engaged something else". The owner of
    /// the open popups dismisses its model here; one handler, because one
    /// thing owns popups at a time (a menu and its submenu are one owner).
    public static func onDismiss(_ handler: (() -> Void)?) {
        dismissHandler = handler
    }

    /// Opens a popup at (x, y) sized (width, height), all in the HOST
    /// window's client logical points — the space menu geometry is already
    /// computed in; the popup may overhang the window freely. Returns the
    /// view id, or nil when the surface could not be created (caller draws
    /// in-window instead).
    /// `holdUntilRevealed` keeps the popup hidden past its first composite,
    /// until `reveal` — for content the owner knows is about to change shape
    /// (a menu whose full verb tier is still being queried), so it appears
    /// once, settled, instead of growing on screen.
    public static func open(x: Double, y: Double, width: Double,
                            height: Double,
                            holdUntilRevealed: Bool = false,
                            content: @escaping () -> Widget) -> Int? {
        guard let host = Win32WindowedHost.host else { return nil }
        installIfNeeded()
        let id = flwin32_popup_open(host.cHost, x, y, width, height)
        guard id > 0 else { return nil }
        builders[Int(id)] = content
        if holdUntilRevealed { held.insert(Int(id)) }
        // The popup's first frame: opening is not itself a build, so kick
        // the engine the same way a programmatic setState does.
        hostScheduleEngineFrame?()
        return Int(id)
    }

    /// Lifts an open's `holdUntilRevealed`. Idempotent; shows immediately
    /// when the view has composited, or on its first composite otherwise.
    public static func reveal(_ id: Int) {
        guard held.remove(id) != nil else { return }
        guard composited.contains(id), let host = Win32WindowedHost.host
        else { return }
        flwin32_popup_show(host.cHost, Int64(id))
    }

    /// Moves/resizes an open popup (a menu growing as the shell's verbs
    /// arrive, "Show more options" expanding in place).
    public static func place(_ id: Int, x: Double, y: Double, width: Double,
                             height: Double) {
        guard let host = Win32WindowedHost.host else { return }
        flwin32_popup_place(host.cHost, Int64(id), x, y, width, height)
    }

    public static func close(_ id: Int) {
        guard let host = Win32WindowedHost.host else { return }
        builders.removeValue(forKey: id)
        composited.remove(id)
        held.remove(id)
        flwin32_popup_close(host.cHost, Int64(id))
    }

    public static func closeAll() {
        guard let host = Win32WindowedHost.host else { return }
        builders.removeAll()
        composited.removeAll()
        held.removeAll()
        flwin32_popup_close_all(host.cHost)
    }

    /// The monitor's work area in host-client logical points (left/top are
    /// negative when the monitor extends past the window's origin, which it
    /// nearly always does). What menu placement clamps against once menus
    /// can leave the window. nil when there is no host yet.
    public static func frame() -> (left: Double, top: Double, right: Double,
                                   bottom: Double)? {
        guard let host = Win32WindowedHost.host else { return nil }
        var l = 0.0, t = 0.0, r = 0.0, b = 0.0
        flwin32_popup_frame(host.cHost, &l, &t, &r, &b)
        guard r > l, b > t else { return nil }
        return (l, t, r, b)
    }
}
#endif
