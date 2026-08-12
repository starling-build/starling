// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import FlutterSwiftBridge

/// Maps framework key events to the byte sequences a terminal expects.
enum TerminalInput {

    // Two numbering schemes reach us, and both have to be recognised.
    //
    // The DRM embedder and the shell's DMA-BUF key forwarding put **X11
    // keysyms** in KeyData.logical (Keysym below). The engine's own embedders
    // — the Win32 one, and the GTK one — put **Flutter logical key ids**
    // there instead (FlutterKey below), which are unrelated values in a
    // dedicated plane above 2^32.
    //
    // Printable characters were unaffected either way, because they fall
    // through to keyData.character. Special keys were not: on Windows every
    // one of them, Enter included, silently produced nothing — you could type
    // at a shell prompt but never run anything.
    //
    // The two ranges cannot collide (keysyms are 16-bit here, Flutter ids are
    // ≥ 0x1_0000_0000), so one switch can serve both and the same binary works
    // under the Starling shell and on Windows.
    private enum Keysym {
        static let backspace: Int64 = 0xFF08
        static let tab: Int64 = 0xFF09
        static let enter: Int64 = 0xFF0D
        static let escape: Int64 = 0xFF1B
        static let home: Int64 = 0xFF50
        static let left: Int64 = 0xFF51
        static let up: Int64 = 0xFF52
        static let right: Int64 = 0xFF53
        static let down: Int64 = 0xFF54
        static let pageUp: Int64 = 0xFF55
        static let pageDown: Int64 = 0xFF56
        static let end: Int64 = 0xFF57
        static let insert: Int64 = 0xFF63
        static let kpEnter: Int64 = 0xFF8D
        static let delete: Int64 = 0xFFFF
        static let f1: Int64 = 0xFFBE  // F1..F12 are contiguous
    }

    /// Flutter logical key ids, as the engine's Win32 and GTK embedders
    /// deliver them. Enter was confirmed on a Windows run (the embedder
    /// reported logical=0x1_0000_000D for physical=0x7_0028); the rest are
    /// Flutter's published logical key table, which assigns the same plane.
    private enum FlutterKey {
        static let backspace: Int64 = 0x1_0000_0008
        static let tab: Int64 = 0x1_0000_0009
        static let enter: Int64 = 0x1_0000_000D
        static let escape: Int64 = 0x1_0000_001B
        static let delete: Int64 = 0x1_0000_007F
        static let arrowDown: Int64 = 0x1_0000_0301
        static let arrowLeft: Int64 = 0x1_0000_0302
        static let arrowRight: Int64 = 0x1_0000_0303
        static let arrowUp: Int64 = 0x1_0000_0304
        static let end: Int64 = 0x1_0000_0305
        static let home: Int64 = 0x1_0000_0306
        static let pageDown: Int64 = 0x1_0000_0307
        static let pageUp: Int64 = 0x1_0000_0308
        static let insert: Int64 = 0x1_0000_0407
        static let numpadEnter: Int64 = 0x2_0000_020D
        static let f1: Int64 = 0x1_0000_0801  // F1..F12 are contiguous
    }

    /// Returns the bytes to write to the PTY for a key press, or nil if the
    /// key is not terminal input (e.g. a bare modifier).
    ///
    /// `appCursor` is the emulator's DECCKM state: arrows/Home/End send
    /// `ESC O x` instead of `ESC [ x` when set.
    static func bytes(for keyData: KeyData, appCursor: Bool) -> [UInt8]? {
        let logical = keyData.logical

        // Special keys first — they take priority over any character the
        // keymap attached to them.
        switch logical {
        case Keysym.enter, Keysym.kpEnter,
             FlutterKey.enter, FlutterKey.numpadEnter:
            return [0x0D]
        case Keysym.backspace, FlutterKey.backspace:
            return [0x7F]
        case Keysym.tab, FlutterKey.tab:
            return [0x09]
        case Keysym.escape, FlutterKey.escape:
            return [0x1B]
        case Keysym.up, FlutterKey.arrowUp:       return _cursor("A", appCursor)
        case Keysym.down, FlutterKey.arrowDown:   return _cursor("B", appCursor)
        case Keysym.right, FlutterKey.arrowRight: return _cursor("C", appCursor)
        case Keysym.left, FlutterKey.arrowLeft:   return _cursor("D", appCursor)
        case Keysym.home, FlutterKey.home:        return _cursor("H", appCursor)
        case Keysym.end, FlutterKey.end:          return _cursor("F", appCursor)
        case Keysym.insert, FlutterKey.insert:     return Array("\u{1B}[2~".utf8)
        case Keysym.delete, FlutterKey.delete:     return Array("\u{1B}[3~".utf8)
        case Keysym.pageUp, FlutterKey.pageUp:     return Array("\u{1B}[5~".utf8)
        case Keysym.pageDown, FlutterKey.pageDown: return Array("\u{1B}[6~".utf8)
        default:
            break
        }

        // Function keys F1-F12, in whichever numbering arrived.
        let fnBase: Int64? =
            (logical >= Keysym.f1 && logical < Keysym.f1 + 12) ? Keysym.f1
            : (logical >= FlutterKey.f1 && logical < FlutterKey.f1 + 12) ? FlutterKey.f1
            : nil
        if let fnBase {
            let n = Int(logical - fnBase)  // 0-based
            switch n {
            case 0: return Array("\u{1B}OP".utf8)
            case 1: return Array("\u{1B}OQ".utf8)
            case 2: return Array("\u{1B}OR".utf8)
            case 3: return Array("\u{1B}OS".utf8)
            default:
                // F5.. use CSI codes with gaps (15,17,18,19,20,21,23,24)
                let codes = [15, 17, 18, 19, 20, 21, 23, 24]
                return Array("\u{1B}[\(codes[n - 4])~".utf8)
            }
        }

        // Character input: the keymap already applied modifiers, so Ctrl+C
        // arrives as 0x03, Shift+a as "A", etc. Write the UTF-8 bytes as-is.
        if let character = keyData.character, !character.isEmpty {
            return Array(character.utf8)
        }

        return nil  // bare modifier or unmapped special key
    }

    private static func _cursor(_ letter: String, _ appCursor: Bool) -> [UInt8] {
        return Array((appCursor ? "\u{1B}O\(letter)" : "\u{1B}[\(letter)").utf8)
    }
}
