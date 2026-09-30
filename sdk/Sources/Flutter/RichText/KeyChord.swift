// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Keyboard normalisation for editors.
//
// Two facts about KeyData drive this file. First, there is no modifier mask:
// Shift/Ctrl/Alt/Meta arrive as their own down/up events and every consumer
// has to remember them. Second, `logical` is numbered two ways: the Starling
// DRM embedder delivers X11 keysyms (Left = 0xFF51) while the engine's own
// Cocoa/GTK/Win32/UIKit embedders deliver Flutter logical key ids
// (ArrowLeft = 0x1_0000_0302). The ranges cannot collide (keysyms are 16-bit,
// Flutter ids ≥ 0x1_0000_0000), so one table serves both — and a widget that
// matches only one of them is silently dead on every other host, which is how
// the Text Editor's arrows came to work on the shell alone.
//
// Letters are the one place both schemes agree: `logical` is the lowercase
// ASCII code (`c` = 0x63) whatever the modifiers, which is what makes
// Ctrl+C/Cmd+C matchable without consulting `character` (Cocoa gives a
// character for Cmd chords; the DRM shell gives a control byte for Ctrl ones).

import FlutterSwiftBridge
import Foundation

public enum NamedKey: Hashable, Sendable {
    case backspace, tab, enter, escape, delete, insert
    case left, right, up, down, home, end, pageUp, pageDown
    case shift, control, alt, meta
    case function(Int)
    case other
}

public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift = KeyModifiers(rawValue: 1)
    public static let control = KeyModifiers(rawValue: 2)
    public static let alt = KeyModifiers(rawValue: 4)
    public static let meta = KeyModifiers(rawValue: 8)

    /// The platform's accelerator key: Cmd on macOS/iOS, Ctrl elsewhere.
    public static var primary: KeyModifiers {
        #if os(macOS) || os(iOS)
        return .meta
        #else
        return .control
        #endif
    }

    /// The platform's word-motion key: Alt/Option on macOS, Ctrl elsewhere.
    public static var word: KeyModifiers {
        #if os(macOS) || os(iOS)
        return .alt
        #else
        return .control
        #endif
    }
}

/// Tracks modifier state across KeyData events and names keys in either
/// numbering scheme.
public final class KeyChordTracker {
    public private(set) var modifiers: KeyModifiers = []

    public init() {}

    /// Feed every KeyData through this first. Returns true when the event
    /// was a modifier key (state updated, nothing else to do).
    @discardableResult
    public func track(_ keyData: KeyData) -> Bool {
        let down = keyData.type == .down || keyData.type == .repeat
        switch Self.named(keyData.logical) {
        case .shift: _set(.shift, down)
        case .control: _set(.control, down)
        case .alt: _set(.alt, down)
        case .meta: _set(.meta, down)
        default: return false
        }
        return true
    }

    /// Drop every modifier — call on focus loss, since the matching key-up
    /// goes to whoever has focus then.
    public func reset() { modifiers = [] }

    private func _set(_ m: KeyModifiers, _ on: Bool) {
        if on { modifiers.insert(m) } else { modifiers.remove(m) }
    }

    public var shift: Bool { modifiers.contains(.shift) }
    public var control: Bool { modifiers.contains(.control) }
    public var alt: Bool { modifiers.contains(.alt) }
    public var meta: Bool { modifiers.contains(.meta) }
    public var primary: Bool { modifiers.contains(.primary) }
    public var word: Bool { modifiers.contains(.word) }

    // MARK: Naming

    public static func named(_ logical: Int64) -> NamedKey {
        switch logical {
        // X11 keysyms (Starling DRM embedder).
        case 0xFF08: return .backspace
        case 0xFF09, 0xFE20: return .tab          // Tab, ISO_Left_Tab
        case 0xFF0D, 0xFF8D: return .enter        // Return, KP_Enter
        case 0xFF1B: return .escape
        case 0xFFFF, 0xFF9F: return .delete       // Delete, KP_Delete
        case 0xFF63, 0xFF9E: return .insert
        case 0xFF51, 0xFF96: return .left
        case 0xFF53, 0xFF98: return .right
        case 0xFF52, 0xFF97: return .up
        case 0xFF54, 0xFF99: return .down
        case 0xFF50, 0xFF95: return .home
        case 0xFF57, 0xFF9C: return .end
        case 0xFF55, 0xFF9A: return .pageUp
        case 0xFF56, 0xFF9B: return .pageDown
        case 0xFFE1, 0xFFE2: return .shift
        case 0xFFE3, 0xFFE4: return .control
        case 0xFFE9, 0xFFEA: return .alt
        case 0xFFE7, 0xFFE8, 0xFFEB, 0xFFEC: return .meta   // Meta_L/R, Super_L/R
        case 0xFFBE ... 0xFFC9: return .function(Int(logical - 0xFFBE) + 1)
        // Flutter logical key ids (Cocoa/GTK/Win32/UIKit embedders).
        case 0x1_0000_0008: return .backspace
        case 0x1_0000_0009: return .tab
        case 0x1_0000_000D, 0x2_0000_020D: return .enter
        case 0x1_0000_001B: return .escape
        case 0x1_0000_007F: return .delete
        case 0x1_0000_0407: return .insert
        case 0x1_0000_0302: return .left
        case 0x1_0000_0303: return .right
        case 0x1_0000_0304: return .up
        case 0x1_0000_0301: return .down
        case 0x1_0000_0306: return .home
        case 0x1_0000_0305: return .end
        case 0x1_0000_0308: return .pageUp
        case 0x1_0000_0307: return .pageDown
        case 0x2_0000_0102, 0x2_0000_0103: return .shift
        case 0x2_0000_0100, 0x2_0000_0101: return .control
        case 0x2_0000_0104, 0x2_0000_0105: return .alt
        case 0x2_0000_0106, 0x2_0000_0107: return .meta
        case 0x1_0000_0801 ... 0x1_0000_080C: return .function(Int(logical - 0x1_0000_0801) + 1)
        default: return .other
        }
    }

    /// The lowercase letter a key represents, whatever the modifiers, or
    /// nil for a non-letter. Both schemes number letters by ASCII.
    public static func letter(_ logical: Int64) -> Character? {
        if logical >= 0x61 && logical <= 0x7A { return Character(UnicodeScalar(UInt8(logical))) }
        if logical >= 0x41 && logical <= 0x5A { return Character(UnicodeScalar(UInt8(logical + 0x20))) }
        return nil
    }

    /// The printable text a key event types, or nil when it is a chord or a
    /// control key. Ctrl chords on the DRM shell arrive as 0x00-0x1F control
    /// bytes; Cmd chords on Cocoa arrive with the bare letter as `character`.
    public func typedText(_ keyData: KeyData) -> String? {
        guard let ch = keyData.character, !ch.isEmpty else { return nil }
        if control || meta { return nil }
        guard let first = ch.unicodeScalars.first else { return nil }
        if first.value < 0x20 || first.value == 0x7F { return nil }
        return ch
    }
}
