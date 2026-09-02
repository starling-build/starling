// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)

/// HID usage → XT set-1 scancode ("qnum"), the keycode space QEMU's
/// `org.qemu.Display1.Keyboard.Press/Release` speaks.
///
/// Generated, not hand-written — regenerate with
///
///     build/tools/gen-hid-qnum.py > shell/Sources/DesktopShellApp/Guest/HidQnum.swift
///
/// which reads keycodemapdb's `data/keymaps.csv` (revision ab223f5d3113, 2024-11-05) and
/// pairs its `USB Keycodes` column with `AT set1 keycode` — the same two
/// columns `keymap-gen code-map … usb qnum` uses.
///
/// Extended scancodes are `0xe0`-prefixed in set 1; QEMU folds the prefix
/// into the high bit, so `0xe01c` (keypad Enter) is qnum `0x9c`. That is the
/// encoding below, and it matches the table the M0 spike drove a real guest
/// with by hand (`docs/windows-vm/dbus-display.py`) on all 110 names the two
/// share — the cross-check that says this file is right.
///
/// Keys arrive at the intercept point as HID usages already
/// (`DesktopShell.routeKey`, `keyData.physical`), so this is one hop, not two.
/// It is deliberately NOT derived from ``HidEvdev`` at runtime: evdev is a
/// third keycode space with its own gaps, and CLAUDE.md records what a second
/// table that must stay in sync costs. `test/hid_qnum.py` asserts every usage
/// ``HidEvdev`` can deliver has a qnum here.
enum HidQnum {

    /// (HID usage page 0x07 code, XT set-1 scancode).
    static let pairs: [(hid: UInt64, qnum: UInt32)] = [
        (0x04, 0x1E),  // A
        (0x05, 0x30),  // B
        (0x06, 0x2E),  // C
        (0x07, 0x20),  // D
        (0x08, 0x12),  // E
        (0x09, 0x21),  // F
        (0x0A, 0x22),  // G
        (0x0B, 0x23),  // H
        (0x0C, 0x17),  // I
        (0x0D, 0x24),  // J
        (0x0E, 0x25),  // K
        (0x0F, 0x26),  // L
        (0x10, 0x32),  // M
        (0x11, 0x31),  // N
        (0x12, 0x18),  // O
        (0x13, 0x19),  // P
        (0x14, 0x10),  // Q
        (0x15, 0x13),  // R
        (0x16, 0x1F),  // S
        (0x17, 0x14),  // T
        (0x18, 0x16),  // U
        (0x19, 0x2F),  // V
        (0x1A, 0x11),  // W
        (0x1B, 0x2D),  // X
        (0x1C, 0x15),  // Y
        (0x1D, 0x2C),  // Z
        (0x1E, 0x02),  // 1
        (0x1F, 0x03),  // 2
        (0x20, 0x04),  // 3
        (0x21, 0x05),  // 4
        (0x22, 0x06),  // 5
        (0x23, 0x07),  // 6
        (0x24, 0x08),  // 7
        (0x25, 0x09),  // 8
        (0x26, 0x0A),  // 9
        (0x27, 0x0B),  // 0
        (0x28, 0x1C),  // Enter
        (0x29, 0x01),  // Esc
        (0x2A, 0x0E),  // Backspace
        (0x2B, 0x0F),  // Tab
        (0x2C, 0x39),  // Space
        (0x2D, 0x0C),  // Minus
        (0x2E, 0x0D),  // Equal
        (0x2F, 0x1A),  // Leftbrace
        (0x30, 0x1B),  // Rightbrace
        (0x31, 0x2B),  // Backslash
        (0x32, 0x2B),  // Backslash
        (0x33, 0x27),  // Semicolon
        (0x34, 0x28),  // Apostrophe
        (0x35, 0x29),  // Grave
        (0x36, 0x33),  // Comma
        (0x37, 0x34),  // Dot
        (0x38, 0x35),  // Slash
        (0x39, 0x3A),  // Capslock
        (0x3A, 0x3B),  // F1
        (0x3B, 0x3C),  // F2
        (0x3C, 0x3D),  // F3
        (0x3D, 0x3E),  // F4
        (0x3E, 0x3F),  // F5
        (0x3F, 0x40),  // F6
        (0x40, 0x41),  // F7
        (0x41, 0x42),  // F8
        (0x42, 0x43),  // F9
        (0x43, 0x44),  // F10
        (0x44, 0x57),  // F11
        (0x45, 0x58),  // F12
        (0x46, 0x54),  // Sysrq
        (0x47, 0x46),  // Scrolllock
        (0x48, 0xC6),  // Pause (extended)
        (0x49, 0xD2),  // Insert (extended)
        (0x4A, 0xC7),  // Home (extended)
        (0x4B, 0xC9),  // Pageup (extended)
        (0x4C, 0xD3),  // Delete (extended)
        (0x4D, 0xCF),  // End (extended)
        (0x4E, 0xD1),  // Pagedown (extended)
        (0x4F, 0xCD),  // Right (extended)
        (0x50, 0xCB),  // Left (extended)
        (0x51, 0xD0),  // Down (extended)
        (0x52, 0xC8),  // Up (extended)
        (0x53, 0x45),  // Numlock
        (0x54, 0xB5),  // Kpslash (extended)
        (0x55, 0x37),  // Kpasterisk
        (0x56, 0x4A),  // Kpminus
        (0x57, 0x4E),  // Kpplus
        (0x58, 0x9C),  // Kpenter (extended)
        (0x59, 0x4F),  // Kp1
        (0x5A, 0x50),  // Kp2
        (0x5B, 0x51),  // Kp3
        (0x5C, 0x4B),  // Kp4
        (0x5D, 0x4C),  // Kp5
        (0x5E, 0x4D),  // Kp6
        (0x5F, 0x47),  // Kp7
        (0x60, 0x48),  // Kp8
        (0x61, 0x49),  // Kp9
        (0x62, 0x52),  // Kp0
        (0x63, 0x53),  // Kpdot
        (0x64, 0x56),  // 102Nd
        (0x65, 0xDD),  // Compose (extended)
        (0x66, 0xDE),  // Power (extended)
        (0x67, 0x59),  // Kpequal
        (0x68, 0x5D),  // F13
        (0x69, 0x5E),  // F14
        (0x6A, 0x5F),  // F15
        (0x6B, 0x55),  // F16
        (0x6C, 0x83),  // F17 (extended)
        (0x6D, 0xF7),  // F18 (extended)
        (0x6E, 0x84),  // F19 (extended)
        (0x6F, 0x5A),  // F20
        (0x70, 0x74),  // F21
        (0x71, 0xF9),  // F22 (extended)
        (0x72, 0x6D),  // F23
        (0x73, 0x6F),  // F24
        (0x74, 0x64),  // Open
        (0x75, 0xF5),  // Help (extended)
        (0x76, 0x9E),  // Menu (extended)
        (0x77, 0x8C),  // Front (extended)
        (0x78, 0xE8),  // Stop (extended)
        (0x79, 0x85),  // Again (extended)
        (0x7A, 0x87),  // Undo (extended)
        (0x7B, 0xBC),  // Cut (extended)
        (0x7C, 0xF8),  // Copy (extended)
        (0x7D, 0x65),  // Paste
        (0x7E, 0xC1),  // Find (extended)
        (0x7F, 0xA0),  // Mute (extended)
        (0x80, 0xB0),  // Volumeup (extended)
        (0x81, 0xAE),  // Volumedown (extended)
        (0x85, 0x7E),  // Kpcomma
        (0x87, 0x73),  // Ro
        (0x88, 0x70),  // Katakanahiragana
        (0x89, 0x7D),  // Yen
        (0x8A, 0x79),  // Henkan
        (0x8B, 0x7B),  // Muhenkan
        (0x8C, 0x5C),  // Kpjpcomma
        (0x90, 0xF2),  // Hangeul (extended)
        (0x91, 0xF1),  // Hanja (extended)
        (0x92, 0x78),  // Katakana
        (0x93, 0x77),  // Hiragana
        (0x94, 0x76),  // Zenkakuhankaku
        (0xB6, 0xF6),  // Kpleftparen (extended)
        (0xB7, 0xFB),  // Kprightparen (extended)
        (0xE0, 0x1D),  // Leftctrl
        (0xE1, 0x2A),  // Shift
        (0xE2, 0x38),  // Leftalt
        (0xE3, 0xDB),  // Leftmeta (extended)
        (0xE4, 0x9D),  // Rightctrl (extended)
        (0xE5, 0x36),  // Rightshift
        (0xE6, 0xB8),  // Rightalt (extended)
        (0xE7, 0xDC),  // Rightmeta (extended)
        (0xE8, 0xA2),  // Playpause (extended)
        (0xE9, 0xA4),  // Stopcd (extended)
        (0xEA, 0x90),  // Previoussong (extended)
        (0xEB, 0x99),  // Nextsong (extended)
        (0xEC, 0x6C),  // Ejectcd
        (0xED, 0xB0),  // Volumeup (extended)
        (0xEE, 0xAE),  // Volumedown (extended)
        (0xEF, 0xA0),  // Mute (extended)
        (0xF0, 0x82),  // Www (extended)
        (0xF1, 0xEA),  // Back (extended)
        (0xF2, 0xE9),  // Forward (extended)
        (0xF3, 0xE8),  // Stop (extended)
        (0xF4, 0xC1),  // Find (extended)
        (0xF5, 0x75),  // Scrollup
        (0xF6, 0x8F),  // Scrolldown (extended)
        (0xF7, 0x88),  // Edit (extended)
        (0xF8, 0xDF),  // Sleep (extended)
        (0xF9, 0x92),  // Screenlock (extended)
        (0xFA, 0xE7),  // Refresh (extended)
        (0xFB, 0xA1),  // Calc (extended)
    ]

    /// HID usage → qnum. Built once, on first use.
    static let qnumForHid: [UInt64: UInt32] = {
        var m = [UInt64: UInt32](minimumCapacity: pairs.count)
        for p in pairs { m[p.hid] = p.qnum }
        return m
    }()

    /// The qnum for a HID usage, or nil for a key the guest has no scancode
    /// for (dropped with one log line at the call site rather than sent as 0,
    /// which is a real scancode).
    static func qnum(forHid hid: UInt64) -> UInt32? { qnumForHid[hid] }
}

#endif  // os(Linux)
