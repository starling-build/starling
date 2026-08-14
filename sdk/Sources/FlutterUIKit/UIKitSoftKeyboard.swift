// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Swift half of the on-screen keyboard: turns what the UIKeyInput
// responder reports into KeyData and posts it where the engine posts its own.
//
// The whole point of routing through PlatformDispatcher.onKeyData rather than
// straight into the terminal is that nothing downstream should be able to tell
// a soft key from a hard one. The engine's key events arrive at
// SwiftRuntimeDelegate.dispatchKeyData, which calls exactly this hook; the
// FocusManager then hands the event to whichever node has focus. Posting here
// means the on-screen keyboard reaches every focusable widget in the framework
// — the terminal today, MacosTextField the moment anything wants one — instead
// of one widget wiring itself to a private path.
//
// See fluikit_keyboard.m for why the keystroke, and not the flutter/textinput
// editing protocol, is the right thing to be delivering.

#if os(iOS)
import Flutter
import FlutterSwiftBridge
import FlutterUIKitBridge
import Foundation

public enum UIKitSoftKeyboard {

    /// Wires the bridge's callback into the framework, and publishes this host
    /// as the one that owns a keyboard. Idempotent; called from `show` too, so
    /// nothing has to remember to install it first.
    public static func install() {
        guard !_installed else { return }
        _installed = true
        fluikit_keyboard_set_callback({ _, text, keysym, shift in
            UIKitSoftKeyboard._deliver(text: text, keysym: keysym, shift: shift != 0)
        }, nil)
        SoftKeyboard.handler = SoftKeyboard.Handler(
            show: { fluikit_keyboard_show() },
            hide: { fluikit_keyboard_hide() },
            isVisible: { fluikit_keyboard_visible() }
        )
    }

    /// Raises the keyboard, and with it the accessory bar.
    public static func show() {
        install()
        fluikit_keyboard_show()
    }

    public static func hide() {
        fluikit_keyboard_hide()
    }

    public static var isVisible: Bool {
        return fluikit_keyboard_visible()
    }

    /// Raise if hidden, dismiss if shown — what a tap on the terminal does.
    public static func toggle() {
        if isVisible { hide() } else { show() }
    }

    private nonisolated(unsafe) static var _installed = false

    private static func _deliver(text: UnsafePointer<CChar>?, keysym: Int32, shift: Bool) {
        // A press and a release, always. Nothing on a touch screen holds a key,
        // but the framework's key model is a state machine over down/up pairs —
        // deliver only the down and a HardwareKeyboard-style listener believes
        // the key is still held for ever, and every later chord is polluted by
        // a modifier nobody is pressing.
        if let text, let string = String(validatingUTF8: text), !string.isEmpty {
            _post(logical: _logical(for: string), character: string, shift: shift)
            return
        }
        guard keysym != 0 else { return }
        _post(logical: Int64(keysym), character: nil, shift: shift)
    }

    private static func _post(logical: Int64, character: String?, shift: Bool) {
        let pd = PlatformDispatcher.instance
        guard let sink = pd.onKeyData else { return }

        // Shift is armed on the bar, so it is not already in the stream as its
        // own event the way a hardware Shift is. Bracket the key with a real
        // down/up pair: TerminalView tracks _shiftDown from these keysyms, and
        // Shift+Tab — Claude Code's permission-mode cycle — is the chord that
        // stops working if it is merely asserted alongside.
        if shift {
            _ = sink(_keyData(logical: _shiftLeft, character: nil, type: .down))
        }
        _ = sink(_keyData(logical: logical, character: character, type: .down))
        _ = sink(_keyData(logical: logical, character: character, type: .up))
        if shift {
            _ = sink(_keyData(logical: _shiftLeft, character: nil, type: .up))
        }
    }

    private static func _keyData(
        logical: Int64, character: String?, type: KeyEventType
    ) -> KeyData {
        return KeyData(
            timeStamp: Date().timeIntervalSince1970,
            type: type,
            // No physical key was pressed, and saying otherwise would name a
            // scancode that did not happen. Consumers here switch on `logical`.
            physical: 0,
            logical: logical,
            // A release carries no character: a listener that appends on every
            // event it sees would otherwise double every letter typed.
            character: type == .up ? nil : character,
            synthesized: false
        )
    }

    /// The logical key for typed text: its first scalar, which is what a
    /// keysym is for the ASCII range. Text is dispatched on `character`
    /// anyway — this only has to avoid colliding with a named key.
    private static func _logical(for string: String) -> Int64 {
        guard let scalar = string.unicodeScalars.first else { return 0 }
        return Int64(scalar.value)
    }

    /// X11 Shift_L, which is one of the two keysyms TerminalView watches for.
    private static let _shiftLeft: Int64 = 0xFFE1
}
#endif
