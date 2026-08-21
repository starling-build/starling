// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The toasts Windows is holding — the notification centre's real content.
//
// Every call here BLOCKS (WinRT init, async polls): callers stay in
// Task.detached, the same bargain as the rest of the status plumbing.

#if os(Windows)
import FlutterWin32Bridge
import Foundation

public struct Win32Toast: Sendable, Equatable, Identifiable {
    /// The listener's id — what removal takes.
    public let id: UInt32
    public let app: String
    public let title: String
    public let body: String
    public let time: Date
}

public enum Win32Notifications {

    public enum Access: Sendable { case allowed, denied, unspecified, unavailable }

    /// Asks on first call, which is what flips a fresh machine to Allowed.
    public static func access() -> Access {
        switch flwin32_notifications_access() {
        case 2: return .allowed
        case 1: return .denied
        case 0: return .unspecified
        default: return .unavailable
        }
    }

    /// The store as it stands, newest first. Empty on refusal — the UI's
    /// empty state is the same picture either way.
    public static func read() -> [Win32Toast] {
        final class Box { var items: [Win32Toast] = [] }
        let box = Box()
        let n = withExtendedLifetime(box) {
            flwin32_notifications_read({ user, id, app, title, body, time in
                let box = Unmanaged<Box>.fromOpaque(user!).takeUnretainedValue()
                box.items.append(Win32Toast(
                    id: id,
                    app: app.map { String(cString: $0) } ?? "",
                    title: title.map { String(cString: $0) } ?? "",
                    body: body.map { String(cString: $0) } ?? "",
                    time: Date(timeIntervalSince1970: TimeInterval(time))))
            }, Unmanaged.passUnretained(box).toOpaque())
        }
        guard n >= 0 else { return [] }
        return box.items.sorted { $0.time > $1.time }
    }

    @discardableResult
    public static func remove(_ id: UInt32) -> Bool {
        flwin32_notification_remove(id) != 0
    }

    /// The notifying app's logo as engine-ready pixels, or nil when the app
    /// has none to give. One store enumeration per call — cache per app.
    public static func appIcon(toastId: UInt32, size: Int = 32) -> Win32Icon.Bitmap? {
        var pixels: UnsafeMutablePointer<UInt8>? = nil
        var w: Int32 = 0, h: Int32 = 0
        guard flwin32_notification_app_icon(toastId, Int32(size), &pixels, &w, &h) != 0,
              let p = pixels else { return nil }
        return Win32Icon.Bitmap(pixels: p, width: Int(w), height: Int(h))
    }

    /// The native panel's "Clear all", the real one — per-id removals,
    /// because the listener's bulk ClearNotifications reports success from a
    /// desktop process while clearing nothing (verified against the store:
    /// RemoveNotification works, the bulk call is a silent no-op).
    @discardableResult
    public static func clearAll() -> Bool {
        var ok = true
        for toast in read() {
            ok = remove(toast.id) && ok
        }
        return ok
    }
}
#endif
