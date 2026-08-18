// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Whether the desktop has this app's WINDOW focused.
//
// That is not the question `FocusNode.hasFocus` answers. A focus node says
// which widget in this app would receive a keystroke, and in a single-surface
// app the answer is "the same one, forever" — the terminal's node holds focus
// whether or not the user has switched to another window entirely. Reading it
// for window activation is why the terminal's cursor went on blinking behind
// the Settings window, twice a second, in a window nobody was looking at.
//
// The value is per PROCESS rather than per view, like the theme and layout
// pushes beside it: a first-party app is one window.
//
// It defaults to ACTIVE and stays that way unless a host says otherwise, so
// every host that does not report activation — the GTK/windowed build, macOS,
// Windows, iOS — behaves exactly as it did before this existed. On the
// Starling desktop the shell pushes it down the child socket; see
// DMABUF_CONTROL_SET_ACTIVE and GpuDmaBufRenderer's read loop.
//
// Listeners are a LIST, deliberately, where the pushes next door
// (`GpuDmaBufRenderer.onThemeChanged` and friends) are single slots. Those are
// claimed by an app's own `main.swift` and there is exactly one interested
// party. This one has a FRAMEWORK consumer — TerminalView — so a single slot
// would mean the widget silently stealing it from the app around it, or the
// app silently stealing it from the widget, depending on who ran last.

import Foundation

public enum WindowActivation {

    /// True while this app's window is the focused one on the desktop.
    ///
    /// Read it to seed state that is built before the first push arrives;
    /// `addListener` for the changes after that.
    public static var isActive: Bool {
        _lock.lock()
        defer { _lock.unlock() }
        return _isActive
    }

    /// Subscribe to activation changes. Callbacks run on the main queue.
    ///
    /// Returns a token to hand back to `removeListener`: a widget unsubscribes
    /// from `dispose`, long after the closure was made, and Swift offers no
    /// way to compare two closures for identity.
    @discardableResult
    public static func addListener(_ listener: @escaping (Bool) -> Void) -> Int {
        _lock.lock()
        defer { _lock.unlock() }
        _nextToken += 1
        _listeners[_nextToken] = listener
        return _nextToken
    }

    public static func removeListener(_ token: Int) {
        _lock.lock()
        _listeners.removeValue(forKey: token)
        _lock.unlock()
    }

    /// A host reports the window's activation.
    ///
    /// Safe from any thread — the child socket is read on one of its own — and
    /// listeners are always delivered on the main queue, where widget state
    /// lives. A repeat of the current value is dropped rather than fanned out:
    /// the shell re-sends on connect as well as on change, and a spurious
    /// "active" would restart a blink the view had just stopped.
    public static func set(_ active: Bool) {
        _lock.lock()
        guard active != _isActive else { _lock.unlock(); return }
        _isActive = active
        let listeners = Array(_listeners.values)
        _lock.unlock()
        guard !listeners.isEmpty else { return }
        let call: () -> Void = { for listener in listeners { listener(active) } }
        DispatchQueue.main.async(
            execute: unsafeBitCast(call, to: (@Sendable () -> Void).self))
    }

    private nonisolated(unsafe) static var _isActive = true
    private nonisolated(unsafe) static var _listeners: [Int: (Bool) -> Void] = [:]
    private nonisolated(unsafe) static var _nextToken = 0
    private nonisolated(unsafe) static let _lock = NSLock()
}
