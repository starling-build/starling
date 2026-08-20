// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The notification area — other people's tray icons, in our dock.
//
// This is the one piece of Windows shell chrome that cannot be redrawn from
// public API: there is no "list the tray icons" call, because the tray is not
// a list anywhere. It is a window of class `Shell_TrayWnd` that apps send
// their icons to, and a shell hosts it by BEING that window. So the moment
// Starling hides explorer's taskbar, every app that lives in the tray —
// Discord, Slack, Teams, OneDrive, a VPN client — becomes unreachable, and
// this is what gives them somewhere to be.
//
// The protocol, the wire format and the traps are in flwin32_tray.c. What is
// worth knowing here: icons arrive over a second or two rather than at once
// (starting broadcasts `TaskbarCreated` and apps answer it in their own
// time), and the shell never acts on an icon itself — a click is forwarded to
// the app, which then does whatever it likes.

#if os(Windows)
import FlutterWin32Bridge
import Foundation

/// One tray icon, as of the moment the list was taken.
public struct Win32TrayIcon: Sendable, Identifiable, Equatable {
    /// Stable for as long as the icon exists. NOT the window or the id the
    /// app registered with: an icon that used a GUID sends its later changes
    /// with neither of those filled in, so the shell needs an identity of its
    /// own.
    public let id: UInt64
    /// What the app calls itself, one line — the tooltip Windows would show.
    /// Multi-line tips ("OneDrive - Personal\nNot signed in") are flattened.
    public let tooltip: String
    /// Bumped when the picture changes but the icon does not: sync progress,
    /// an unread badge, a connection going green. Part of any cache key.
    public let generation: UInt32
}

public enum Win32Tray {
    /// Takes over the tray. `onChange` runs on the UI thread when the set of
    /// icons changes; ask for `icons()` then.
    ///
    /// Nothing appears immediately. There is no way to enumerate what is
    /// already there, so this broadcasts the message that asks every app to
    /// re-add its own, and they answer over the following second or two.
    @discardableResult
    public static func start(onChange: @escaping () -> Void) -> Bool {
        changeHandler = onChange
        return flwin32_tray_start({ _ in Win32Tray.changeHandler?() }, nil) != 0
    }

    /// Hands the tray back to explorer, and asks every app to re-register with
    /// it. Not doing that would leave the machine with a tray missing
    /// everything that had registered with us.
    public static func stop() {
        flwin32_tray_stop()
        changeHandler = nil
    }

    /// The icons, without their pictures — cheap, and safe to call on the UI
    /// thread. Use `rasterize` for the pixels.
    public static func icons() -> [Win32TrayIcon] {
        guard let list = flwin32_tray_list() else { return [] }
        defer { flwin32_tray_list_free(list) }
        return read(list)
    }

    /// The icons, each with an OWNED icon handle: the caller must destroy
    /// every one of them (`Win32Icon.destroy`) or hand them somewhere that
    /// will. A handle rather than pixels because rasterizing is a GDI draw
    /// per icon and belongs off the UI thread, by which time the snapshot
    /// that produced it is long gone.
    public static func snapshot() -> [(icon: Win32TrayIcon, handle: UInt64)] {
        guard let list = flwin32_tray_list() else { return [] }
        defer { flwin32_tray_list_free(list) }
        return read(list).enumerated().map { index, icon in
            (icon, flwin32_tray_list_take_icon(list, Int32(index)))
        }
    }

    /// Tells the icon's owner the mouse was over it, and nothing else — the
    /// shell never acts on a tray icon itself. The app is told the cursor's
    /// position, which is the icon's, and puts its menu there.
    public static func click(_ id: UInt64, button: Win32TrayButton = .left) {
        flwin32_tray_click(id, Int32(button.rawValue))
    }

    private static func read(_ list: OpaquePointer) -> [Win32TrayIcon] {
        let count = Int(flwin32_tray_list_count(list))
        var out: [Win32TrayIcon] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            var buffer = [CChar](repeating: 0, count: 512)
            let tip = flwin32_tray_list_tip(list, Int32(i), &buffer, 512) != 0
                ? String(cString: buffer) : ""
            out.append(Win32TrayIcon(id: flwin32_tray_list_key(list, Int32(i)),
                                     tooltip: tip,
                                     generation: flwin32_tray_list_generation(list, Int32(i))))
        }
        return out
    }

    /// Global for the same reason the toggle handler is: one UI thread, one
    /// tray window per process.
    nonisolated(unsafe) private static var changeHandler: (() -> Void)?
}

public enum Win32TrayButton: Int, Sendable {
    case left = 0
    case right = 1
    case middle = 2
}
#endif
