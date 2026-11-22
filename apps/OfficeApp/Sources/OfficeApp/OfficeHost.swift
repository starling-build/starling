// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// What a host that owns the window's native frame (the iPad's document
// browser) can ask of, and tell, the editors. Plain closures, so the shells
// need no knowledge of UIKit and every other platform leaves them nil — the
// Backstage panels keep working exactly as before.

import Foundation
import OfficeText

enum OfficeHost {
    /// The editors have just written the user's document at `path`.
    /// Set by a host that keeps its own copy of the file.
    static var documentSaved: ((String) -> Void)?

    /// The user asked for Open (or Close). Returns true if the host took it
    /// over, so the editor does not show its own file panel.
    static var openRequested: (() -> Bool)?

    /// Set by OfficeRoot while mounted: switch the whole window to the
    /// document at `path`, whatever its kind.
    static var openPath: ((String) -> Void)?

    /// Writes an empty document of `kind` to `path`. Used by the host's own
    /// "New" so a blank file exists before the editor opens it.
    static func writeBlank(kind: String, to path: String) -> Bool {
        do {
            switch kind {
            case "presentation":
                let deck = DeckController()
                deck.newDeck()
                try Pptx.write(deck).write(to: URL(fileURLWithPath: path))
            case "workbook":
                try Xlsx.write(Workbook()).write(to: URL(fileURLWithPath: path))
            default:
                var blank = RichDocument()
                blank.styles = OfficeStyles.sheet
                try OfficeFormats.write(blank, to: path)
            }
            return true
        } catch {
            fputs("[office] could not write a blank \(kind): \(error)\n", stderr)
            return false
        }
    }
}
