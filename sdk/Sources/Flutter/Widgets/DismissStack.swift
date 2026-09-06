// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Escape puts the topmost transient surface away.
//
// Windows closes a flyout, a menu, a combo box's list and a ContentDialog on
// Esc, and this framework's did not: the focus system routes a key to the
// focused node and nowhere else, so with nothing focused Esc went unheard,
// and with a text box focused the box merely unfocused itself (the Files
// New-folder dialog: Esc emptied the caret and the dialog stayed).
//
// This is the missing piece, kept deliberately small — not Flutter's
// Actions/Shortcuts, just a stack of "what Esc closes right now". Whatever
// opens a transient surface pushes a closer and pops it when the surface
// goes away on its own; `FocusManager.dispatchKeyData` hands an unclaimed
// Escape to the top of the stack. Flyouts (`FlyoutController.showFlyout`)
// and modal routes (`ModalRoute`, so every `showDialog`) do this
// themselves; a widget with its own popup can too.

import FlutterSwiftBridge

public enum DismissStack {
    /// A registration, so a closer can be removed from the middle of the
    /// stack when its surface closes by other means (a click on the
    /// barrier, a menu item chosen) while something newer is still up.
    public struct Token: Equatable {
        fileprivate let id: Int
    }

    private nonisolated(unsafe) static var _entries: [(id: Int, close: () -> Void)] = []
    private nonisolated(unsafe) static var _next = 1

    /// Registers what Esc should close next.
    @discardableResult
    public static func push(_ close: @escaping () -> Void) -> Token {
        let id = _next
        _next += 1
        _entries.append((id, close))
        return Token(id: id)
    }

    /// Unregisters a closer; harmless if it has already been popped.
    public static func remove(_ token: Token?) {
        guard let token else { return }
        _entries.removeAll { $0.id == token.id }
    }

    /// Whether anything is waiting on Esc.
    public static var isEmpty: Bool { _entries.isEmpty }

    /// Closes the topmost surface. Returns false when there was none.
    @discardableResult
    public static func dismissTop() -> Bool {
        guard let top = _entries.popLast() else { return false }
        top.close()
        return true
    }

    /// Escape, on whichever host: the HID usage a shell or the DRM embedder
    /// reports as `physical`, or the X11 keysym / Flutter logical key a
    /// child app sees in `logical`.
    public static func isEscape(_ data: KeyData) -> Bool {
        data.physical == 0x0007_0029
            || data.physical == 0x29
            || data.logical == 0xFF1B
            || data.logical == 0x1_0000_001B
            || data.logical == 0x1B
    }
}
