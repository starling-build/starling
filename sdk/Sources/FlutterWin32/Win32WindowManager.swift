// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Other people's windows: enumerate them, move them, raise them, watch them.
//
// This is the Windows stand-in for the half of the Starling desktop that on
// Linux is the compositor. DWM cannot be replaced, so the shell does not own
// anyone's pixels here — it owns their *geometry*, through user32. The
// mechanism lives in FlutterWin32Bridge (flwin32_wm.c) and is deliberately
// policy-free: which windows go where is the shell's business, and the
// desktop already has 1,092 lines of it in WindowManager.swift with no
// platform code in them at all. This is what that will sit on.

#if os(Windows)
import FlutterWin32Bridge
import Foundation

/// A rectangle in virtual-desktop pixels — the coordinate space Windows lays
/// monitors out in, so `x`/`y` are negative for a screen left of or above the
/// primary. The same convention as `Win32Monitor`.
public struct Win32Rect: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// One managed window, as of the moment the list was taken.
///
/// A value type on purpose: an HWND is only valid until the window closes, so
/// anything that holds one is holding a fact that may already be stale. Ask
/// for a fresh list rather than caching these.
public struct Win32Window: Sendable, Equatable, Identifiable {
    /// The HWND. Opaque — the only thing to do with it is hand it back.
    public let handle: UInt64
    public var id: UInt64 { handle }
    public let pid: UInt32
    public let title: String
    /// The window class, which is the closest Windows has to Wayland's
    /// `app_id`: stable per app, unlike the title. `Chrome_WidgetWin_1`,
    /// `CASCADIA_HOSTING_WINDOW_CLASS`, `SunAwtFrame`.
    public let className: String
    /// Full path to the owning process's image, or "" when the process
    /// refused to be opened (a service, or a higher integrity level).
    public let executablePath: String
    /// The frame as the user sees it — DWM's extended bounds, with the
    /// invisible Windows 10+ resize border already taken off.
    public let frame: Win32Rect
    /// Index into `Win32Display.monitors()`, or nil if the window is not on
    /// any monitor Windows will admit to.
    public let monitor: Int?
    public let isMinimized: Bool
    public let isMaximized: Bool
    public let isForeground: Bool

    /// What a dock would label it: the executable's base name without the
    /// extension, falling back to the window class. Not the title — a title
    /// is a document, not an app (`untitled – Main.java` is the standing
    /// example in the desktop's own notes).
    public var appName: String {
        guard !executablePath.isEmpty else { return className }
        let base = executablePath.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last
        guard let base else { return className }
        if let dot = base.lastIndex(of: "."), dot != base.startIndex {
            return String(base[base.startIndex..<dot])
        }
        return String(base)
    }
}

/// What changed. Every case carries the window it happened to; none of them
/// carry the window's new state, because by the time the handler runs it may
/// have changed again — re-read the list.
public enum Win32WindowEvent: Sendable, Equatable {
    /// A manageable window appeared (created, shown, or uncloaked — a
    /// virtual-desktop switch shows up as the last of those).
    case added(UInt64)
    /// Destroyed, hidden or cloaked. Not necessarily one we were tracking:
    /// the handle is already dead, so it cannot be tested, and reconciling
    /// against your own list is the only correct response.
    case removed(UInt64)
    case foregroundChanged(UInt64)
    case titleChanged(UInt64)
    /// A user drag or resize *finished*. Continuous motion is deliberately
    /// not reported — see flwin32_wm_watch.
    case moved(UInt64)
    case minimizedChanged(UInt64)
}

public enum Win32WindowManager {

    // MARK: - Reading

    /// The manageable top-level windows, in z-order, topmost first — the
    /// same set and order a taskbar or Alt+Tab shows.
    ///
    /// This walks every top-level window in the session and asks DWM about
    /// each one, so it is not free (single-digit milliseconds on a normal
    /// desktop). Call it on a change, not on a frame.
    public static func windows() -> [Win32Window] {
        guard let list = flwin32_wm_snapshot() else { return [] }
        defer { flwin32_wm_release(list) }

        let count = Int(flwin32_wm_count(list))
        var out: [Win32Window] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            var info = FlWin32WindowInfo()
            guard flwin32_wm_info(list, Int32(i), &info) != 0 else { continue }
            out.append(Win32Window(
                handle: info.handle,
                pid: info.pid,
                title: readString(list, Int32(i), flwin32_wm_title),
                className: readString(list, Int32(i), flwin32_wm_class),
                executablePath: readString(list, Int32(i), flwin32_wm_exe),
                frame: Win32Rect(x: Int(info.x), y: Int(info.y),
                                 width: Int(info.width), height: Int(info.height)),
                monitor: info.monitor >= 0 ? Int(info.monitor) : nil,
                isMinimized: info.minimized != 0,
                isMaximized: info.maximized != 0,
                isForeground: info.foreground != 0))
        }
        return out
    }

    /// The focused window's handle, or 0 when the foreground belongs to no
    /// one (it briefly does, during a desktop switch or a UAC prompt).
    public static var foreground: UInt64 { flwin32_wm_foreground() }

    /// A monitor's work area: its rectangle minus the taskbar and any
    /// appbars — including our own bar, once it has registered. This is the
    /// rectangle a tiler should divide, and reading it rather than the
    /// monitor rectangle is what makes Starling chrome and explorer's
    /// taskbar coexist instead of overlapping.
    public static func workArea(monitor: Int? = nil) -> Win32Rect? {
        var x: Int32 = 0, y: Int32 = 0, w: Int32 = 0, h: Int32 = 0
        guard flwin32_wm_work_area(Int32(monitor ?? -1), &x, &y, &w, &h) != 0
        else { return nil }
        return Win32Rect(x: Int(x), y: Int(y), width: Int(w), height: Int(h))
    }

    // MARK: - Acting

    /// Raises the window and gives it the keyboard, restoring it first if it
    /// was minimized.
    @discardableResult
    public static func activate(_ handle: UInt64) -> Bool {
        flwin32_wm_activate(handle) != 0
    }

    /// Places the window so its *visible* frame is `rect`. Un-maximizes
    /// first, because a maximized window snaps back from any placement.
    @discardableResult
    public static func move(_ handle: UInt64, to rect: Win32Rect) -> Bool {
        flwin32_wm_move(handle, Int32(rect.x), Int32(rect.y),
                        Int32(rect.width), Int32(rect.height)) != 0
    }

    @discardableResult
    public static func minimize(_ handle: UInt64) -> Bool {
        flwin32_wm_set_state(handle, 1) != 0
    }

    @discardableResult
    public static func maximize(_ handle: UInt64) -> Bool {
        flwin32_wm_set_state(handle, 2) != 0
    }

    @discardableResult
    public static func restore(_ handle: UInt64) -> Bool {
        flwin32_wm_set_state(handle, 0) != 0
    }

    /// Asks the window to close, the way its X button does — the app may
    /// prompt or refuse. There is no kill here on purpose.
    @discardableResult
    public static func close(_ handle: UInt64) -> Bool {
        flwin32_wm_close(handle) != 0
    }

    // MARK: - Watching

    /// Handlers are global because the hooks are: `SetWinEventHook` delivers
    /// to the installing *thread*, and there is exactly one UI thread.
    nonisolated(unsafe) private static var handler: ((Win32WindowEvent) -> Void)?

    /// Starts reporting window-list changes. The handler runs on the UI
    /// thread, inside the host's message loop, so it may touch the widget
    /// tree directly.
    ///
    /// Call after the host exists — the hooks attach to whichever thread
    /// calls this, and before `runStarlingApp` that is not yet the thread the
    /// message loop will run on.
    @discardableResult
    public static func observe(_ handler: @escaping (Win32WindowEvent) -> Void) -> Bool {
        Self.handler = handler
        let trampoline: FlWin32WmEventCallback = { kind, handle, _ in
            guard let h = Win32WindowManager.handler else { return }
            switch kind {
            case FLWIN32_WM_EVENT_ADDED: h(.added(handle))
            case FLWIN32_WM_EVENT_REMOVED: h(.removed(handle))
            case FLWIN32_WM_EVENT_FOREGROUND: h(.foregroundChanged(handle))
            case FLWIN32_WM_EVENT_TITLE: h(.titleChanged(handle))
            case FLWIN32_WM_EVENT_MOVED: h(.moved(handle))
            case FLWIN32_WM_EVENT_MINIMIZED: h(.minimizedChanged(handle))
            default: break
            }
        }
        if flwin32_wm_watch(trampoline, nil) == 0 {
            Self.handler = nil
            return false
        }
        return true
    }

    public static func stopObserving() {
        flwin32_wm_unwatch()
        handler = nil
    }

    // MARK: - Private

    /// The bridge's copy-out convention: -1 means "too small, try again".
    /// Titles are usually well under 256 bytes; a path plus a UTF-8 title
    /// occasionally is not, so grow rather than truncate.
    private static func readString(
        _ list: OpaquePointer,
        _ index: Int32,
        _ read: (OpaquePointer?, Int32, UnsafeMutablePointer<CChar>?, Int32) -> Int32
    ) -> String {
        var size = 512
        while size <= 65536 {
            var buffer = [CChar](repeating: 0, count: size)
            let n = buffer.withUnsafeMutableBufferPointer {
                read(list, index, $0.baseAddress, Int32(size))
            }
            if n > 0 { return String(cString: buffer) }
            if n == 0 { return "" }
            size *= 4
        }
        return ""
    }
}
#endif
