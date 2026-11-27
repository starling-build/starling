// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// What the primary-modifier + V chord does in Writer (W-P0-5). Word keeps
/// Ctrl+Shift+C / Ctrl+Shift+V for the Format Painter's copy and paste, and
/// gives Paste Special Ctrl+Alt+V (W-ED-1: its dialog lists the clipboard's
/// formats, Unformatted Text among them).
public enum PasteChord: Equatable {
    case paste, pasteFormat, pasteSpecial

    public static func of(shift: Bool, alt: Bool) -> PasteChord {
        if alt { return .pasteSpecial }
        return shift ? .pasteFormat : .paste
    }
}
