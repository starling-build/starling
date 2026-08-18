// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation

/// The one HID ↔ evdev keycode table, and both directions derived from it.
///
/// These two mappings must be exact inverses. They were separate switches —
/// `WaylandIntegration.hidToEvdev` here, `FlDrmInput::EvdevToHID` in the
/// engine — and CLAUDE.md records what that costs: change one, forget the
/// other, and letters break for Wayland clients while the shell's own UI
/// looks fine. Display mode needs the evdev→HID direction too (RDP delivers
/// scancodes, the engine wants HID), which would have been a third copy.
///
/// So: one array of pairs, two lookups built from it at first use. A key
/// added here is added to every direction at once, and cannot drift.
enum HidEvdev {

    /// (HID usage page 0x07 code, Linux evdev keycode).
    static let pairs: [(hid: UInt64, evdev: UInt32)] = [
        (0x29, 1),  // Escape
        (0x1E, 2),  // 1
        (0x1F, 3),  // 2
        (0x20, 4),  // 3
        (0x21, 5),  // 4
        (0x22, 6),  // 5
        (0x23, 7),  // 6
        (0x24, 8),  // 7
        (0x25, 9),  // 8
        (0x26, 10),  // 9
        (0x27, 11),  // 0
        (0x2D, 12),  // -
        (0x2E, 13),  // =
        (0x2A, 14),  // Backspace
        (0x2B, 15),  // Tab
        (0x14, 16),  // Q
        (0x1A, 17),  // W
        (0x08, 18),  // E
        (0x15, 19),  // R
        (0x17, 20),  // T
        (0x1C, 21),  // Y
        (0x18, 22),  // U
        (0x0C, 23),  // I
        (0x12, 24),  // O
        (0x13, 25),  // P
        (0x2F, 26),  // [
        (0x30, 27),  // ]
        (0x28, 28),  // Enter
        (0xE0, 29),  // Left Control
        (0x04, 30),  // A
        (0x16, 31),  // S
        (0x07, 32),  // D
        (0x09, 33),  // F
        (0x0A, 34),  // G
        (0x0B, 35),  // H
        (0x0D, 36),  // J
        (0x0E, 37),  // K
        (0x0F, 38),  // L
        (0x33, 39),  // ;
        (0x34, 40),  // '
        (0x35, 41),  // `
        (0xE1, 42),  // Left Shift
        (0x31, 43),  // backslash
        (0x1D, 44),  // Z
        (0x1B, 45),  // X
        (0x06, 46),  // C
        (0x19, 47),  // V
        (0x05, 48),  // B
        (0x11, 49),  // N
        (0x10, 50),  // M
        (0x36, 51),  // ,
        (0x37, 52),  // .
        (0x38, 53),  // /
        (0xE5, 54),  // Right Shift
        (0x55, 55),  // KP *
        (0xE2, 56),  // Left Alt
        (0x2C, 57),  // Space
        (0x39, 58),  // CapsLock
        (0x3A, 59),  // F1
        (0x3B, 60),  // F2
        (0x3C, 61),  // F3
        (0x3D, 62),  // F4
        (0x3E, 63),  // F5
        (0x3F, 64),  // F6
        (0x40, 65),  // F7
        (0x41, 66),  // F8
        (0x42, 67),  // F9
        (0x43, 68),  // F10
        (0x53, 69),  // NumLock
        (0x47, 70),  // ScrollLock
        (0x5F, 71),  // KP 7
        (0x60, 72),  // KP 8
        (0x61, 73),  // KP 9
        (0x56, 74),  // KP -
        (0x5C, 75),  // KP 4
        (0x5D, 76),  // KP 5
        (0x5E, 77),  // KP 6
        (0x57, 78),  // KP +
        (0x59, 79),  // KP 1
        (0x5A, 80),  // KP 2
        (0x5B, 81),  // KP 3
        (0x62, 82),  // KP 0
        (0x63, 83),  // KP .
        (0x44, 87),  // F11
        (0x45, 88),  // F12
        (0x58, 96),  // KP Enter
        (0xE4, 97),  // Right Control
        (0x54, 98),  // KP /
        (0x46, 99),  // PrintScreen
        (0xE6, 100),  // Right Alt
        (0x4A, 102),  // Home
        (0x52, 103),  // Up
        (0x4B, 104),  // PageUp
        (0x50, 105),  // Left
        (0x4F, 106),  // Right
        (0x4D, 107),  // End
        (0x51, 108),  // Down
        (0x4E, 109),  // PageDown
        (0x49, 110),  // Insert
        (0x4C, 111),  // Delete
        (0x48, 119),  // Pause
        (0xE3, 125),  // Left Meta
        (0xE7, 126),  // Right Meta
        (0x65, 127),  // Menu/Compose
    ]

    private static let hidMap: [UInt64: UInt32] = {
        var m = [UInt64: UInt32](minimumCapacity: pairs.count)
        for p in pairs { m[p.hid] = p.evdev }
        return m
    }()

    private static let evdevMap: [UInt32: UInt64] = {
        var m = [UInt32: UInt64](minimumCapacity: pairs.count)
        for p in pairs { m[p.evdev] = p.hid }
        return m
    }()

    /// HID → evdev. Codes carrying the 0x100000000 flag are unmapped
    /// passthroughs from the engine and keep their original evdev value.
    static func evdev(fromHid hid: UInt64) -> UInt32 {
        if hid & 0x100000000 != 0 {
            return UInt32(hid & 0xFFFFFFFF)
        }
        return hidMap[hid] ?? UInt32(hid & 0xFF)
    }

    /// evdev → HID. Anything unmapped is flagged rather than guessed, which
    /// is what lets the reverse trip recover the original code instead of
    /// inventing a key.
    static func hid(fromEvdev evdev: UInt32) -> UInt64 {
        return evdevMap[evdev] ?? (UInt64(evdev) | 0x100000000)
    }
}
#endif
