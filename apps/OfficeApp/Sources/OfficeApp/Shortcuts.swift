// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Shortcut hints as the platform writes them. The app's strings spell a
// chord the Mac way ("Save (⌘S)", "⇧⌘Z", "⌘-click"); everywhere else the
// accelerator is Ctrl and chords are written out ("Ctrl+S", "Ctrl+Shift+Z",
// "Ctrl-click"), which is what `KeyModifiers.primary` actually answers to.

extension String {
    /// This text with its Mac chord glyphs rewritten for the platform.
    var keys: String {
        #if os(macOS) || os(iOS)
        return self
        #else
        let names: [Character: String] = ["⌃": "Ctrl", "⌘": "Ctrl", "⌥": "Alt", "⇧": "Shift"]
        var out = ""
        var held: [String] = []
        func flush(before next: Character?) {
            guard !held.isEmpty else { return }
            // Ctrl, Alt, Shift — the order Windows menus use.
            let ordered = ["Ctrl", "Alt", "Shift"].filter(held.contains)
            // "⌘-click" is a held key and a click, not a chord with "-".
            out += ordered.joined(separator: "+") + (next == "-" ? "" : "+")
            held = []
        }
        for ch in self {
            if let name = names[ch] {
                if !held.contains(name) { held.append(name) }
            } else {
                flush(before: ch)
                out.append(ch)
            }
        }
        flush(before: "-")
        return out
        #endif
    }
}
