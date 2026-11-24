// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// What the primary-modifier + V chord does in Writer (W-P0-5). Word keeps
/// Ctrl+Shift+C / Ctrl+Shift+V for the Format Painter's copy and paste, and
/// gives Paste Special Ctrl+Alt+V; with no Paste Special dialog yet, that
/// chord pastes the clipboard's text alone.
public enum PasteChord: Equatable {
    case paste, pasteFormat, pastePlainText

    public static func of(shift: Bool, alt: Bool) -> PasteChord {
        if alt { return .pastePlainText }
        return shift ? .pasteFormat : .paste
    }
}
