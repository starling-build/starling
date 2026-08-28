// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Keyboard routing between the shell's surfaces.
//
// WHY THIS EXISTS. `PlatformDispatcher.instance.onKeyData` is ONE slot, not a
// listener list: assigning it replaces whatever was there. Two surfaces
// assigned it directly -- the file explorer and the desktop -- each with the
// same comment saying "this window owns its process, so the process-wide hook
// is ours". That was true when every surface was its own process. It stopped
// being true when the shell became one process with several views (the dock's
// chrome, the desktop, and the file explorer all live in the `--oneview`
// process), and nothing warns you: the second assignment silently takes the
// keyboard away from the first.
//
// What it looked like from outside, measured on the box: open the file
// explorer with Win+E and its keyboard works; hide it and bring it back, and
// EVERY shortcut is dead -- Ctrl+A, F2, Escape -- while the mouse still works
// perfectly. The Escape half of that is the one people noticed, because a
// context menu that will not close on Escape is right in front of you.
//
// THE RULE HERE: the surface whose window holds the FOREGROUND gets the keys.
// Not the last one to start, which is what the single slot amounted to, and
// not everyone at once, which would have the desktop deleting an icon while
// someone is renaming a file. Registration is per surface and additive, so a
// third surface joining cannot take the keyboard off the other two.
//
// The foreground is asked at key time rather than tracked, because there is
// no activation callback to track it with -- the host offers onDeactivate and
// nothing for the other direction -- and a stale answer here is a dead
// keyboard, which is exactly the bug this file exists to end.

#if os(Windows)
import Flutter
import FlutterSwiftBridge
import FlutterWin32

enum ShellKeys {
    private struct Listener {
        /// The window this surface's keys belong to. A closure rather than a
        /// value: a surface's window can be made after it registers.
        let window: () -> UInt64
        let handle: (KeyData) -> Bool
    }

    private static var listeners: [Listener] = []

    /// Registers one surface's shortcut handler. Call once, from initState.
    ///
    /// `window` names the surface's own top-level window; `handle` is what
    /// used to be assigned straight onto the dispatcher.
    static func register(window: @escaping () -> UInt64,
                         handle: @escaping (KeyData) -> Bool) {
        listeners.append(Listener(window: window, handle: handle))
        // Installed on every register, not once: the last writer of the slot
        // is then always this router rather than a surface that assigned it
        // directly, however the registrations interleave.
        PlatformDispatcher.instance.onKeyData = { keyData in
            // Focused fields still come first, exactly as before -- a text
            // field being typed into owns the keyboard over any shortcut.
            if FocusManager.instance.dispatchKeyData(keyData) { return true }
            let foreground = Win32WindowManager.foreground
            for listener in listeners where listener.window() == foreground {
                if listener.handle(keyData) { return true }
            }
            return false
        }
    }
}
#endif
