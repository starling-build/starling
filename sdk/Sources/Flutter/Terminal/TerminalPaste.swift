// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// What a paste means in a field that holds ONE line.
//
// The terminal has two of them — the find bar here, and the workspace
// switcher in the app — and a clipboard almost never holds exactly what such
// a field wants. Text copied out of a terminal, a config file or a browser
// arrives with a newline on the end at best, and with a whole transcript at
// worst. Both fields also treat Enter as a verb (run the search, open the
// workspace), so a stray newline is not a character to pass through.
//
// One definition, used by both, because the alternative is two that agree
// until one of them is edited.

import Foundation

/// The clipboard, as a one-line field can use it.
public enum TerminalPaste {

    /// What `text` contributes to a single-line field with `room` characters
    /// left in it.
    ///
    /// The first line with anything on it wins and the rest is dropped —
    /// joining the lines of a shell transcript would produce something that
    /// is not a query or a destination in any spelling. C0 goes the same way:
    /// nothing unprintable belongs in a search term, a hostname, a path or an
    /// ssh flag, and a tab or an escape landing mid-field would draw as a hole
    /// nobody could account for.
    public static func oneLine(_ text: String, room: Int) -> String {
        guard room > 0 else { return "" }
        let line = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let printable = String(String.UnicodeScalarView(
            line.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }))
        return String(printable.trimmingCharacters(in: .whitespaces).prefix(room))
    }
}
