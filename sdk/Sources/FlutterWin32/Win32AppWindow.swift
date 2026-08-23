// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The window an app's tree lives in — whichever kind that is.
//
// An app that draws its own titlebar has to act on ITS window: drag it,
// maximize it, close it, and lay out against its client size. For a process
// with one window that is `Win32WindowedHost.host` and the distinction never
// comes up. It comes up the moment the same tree can also be a VIEW inside
// the shell's process, where the host's window is the DOCK — there, a
// titlebar drag would drag the dock and a close button would close the
// desktop.
//
// So the tree holds one of these instead of reaching for the host. Both cases
// are the same handle-addressed operations underneath
// (flwin32_window_* in the bridge); what differs is only which handle.

#if os(Windows)
import FlutterWin32Bridge
import Foundation

public struct Win32AppWindow: Sendable {
    /// The surface view this window belongs to, or nil when the tree owns the
    /// process's main window. Kept because a few things are still addressed
    /// by view id rather than by handle.
    public let surfaceId: Int?

    private let hwnd: UInt64

    /// The process's main window — the single-window case, and the default.
    public static var main: Win32AppWindow {
        Win32AppWindow(surfaceId: nil,
                       hwnd: Win32WindowedHost.host?.windowHandle ?? 0)
    }

    /// A surface view's own window, for a tree hosted inside another
    /// process's engine.
    public static func surface(_ id: Int) -> Win32AppWindow {
        Win32AppWindow(surfaceId: id, hwnd: Win32Surfaces.windowHandle(id))
    }

    private init(surfaceId: Int?, hwnd: UInt64) {
        self.surfaceId = surfaceId
        self.hwnd = hwnd
    }

    public var handle: UInt64 { hwnd }
    public var isValid: Bool { hwnd != 0 }

    /// Client size in LOGICAL points — what a tree lays out against.
    public var clientSize: (width: Double, height: Double)? {
        guard hwnd != 0 else { return nil }
        var w = 0.0, h = 0.0
        guard flwin32_window_client_size(hwnd, &w, &h) != 0 else { return nil }
        return (w, h)
    }

    public var isMaximized: Bool { flwin32_window_is_maximized(hwnd) != 0 }

    /// Hand the press to the frame as a caption click; Windows runs its own
    /// move loop from there, snap layouts included. Call during pointer-down.
    public func beginDrag() { flwin32_window_begin_drag(hwnd) }
    public func minimize() { flwin32_window_minimize(hwnd) }
    public func toggleMaximize() { flwin32_window_toggle_maximize(hwnd) }

    /// Asks the window to close. What that MEANS is the window's business: a
    /// process's main window exits, an app surface inside the shell hides
    /// itself so the next open is a ShowWindow on a tree that is already
    /// composited.
    public func close() { flwin32_window_close(hwnd) }
}
#endif
