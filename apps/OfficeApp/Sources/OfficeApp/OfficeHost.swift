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

    /// The host's own "put a copy somewhere" panel (the iPad's document
    /// picker, which can reach iCloud Drive and other apps' folders the way an
    /// in-app file list over the sandbox cannot). `name` is the suggested file
    /// name; `prepare` writes the file to the path it is given and calls its
    /// completion with whether that worked (it may finish later: a PDF is
    /// made asynchronously); `thenOpen` is Save As — the editor carries on in
    /// the copy — against Export, which leaves the document as it is. `done`
    /// gets the chosen file's name, or nil if the user cancelled or it failed.
    /// Set by a host that has such a panel; nil elsewhere, where the Backstage
    /// panels stay.
    static var exportRequested: ((_ name: String,
                                  _ prepare: @escaping (_ path: String, _ finished: @escaping (Bool) -> Void) -> Void,
                                  _ thenOpen: Bool,
                                  _ done: @escaping (String?) -> Void) -> Void)?

    /// One button of the native toolbar over the on-screen keyboard. `symbol`
    /// is an SF Symbol name; state is a snapshot, re-published when it changes.
    struct ToolbarButton {
        let id: String
        let title: String
        let symbol: String
        var isOn = false
        var isEnabled = true
        let action: () -> Void
    }

    /// Set by a host that draws a native toolbar. The editor in front
    /// publishes its buttons through it, and publishes nil when it goes away,
    /// so a deck or a workbook shows none.
    static var toolbarChanged: (([ToolbarButton]?) -> Void)?

    private nonisolated(unsafe) static var toolbarOwner: ObjectIdentifier?

    /// Publish `buttons` for `owner`, or withdraw them (nil). A new editor
    /// mounts before the one it replaces is disposed, so a withdrawal counts
    /// only from whoever published last; otherwise the old one's dispose would
    /// wipe the new one's bar.
    static func publishToolbar(_ buttons: [ToolbarButton]?, owner: AnyObject) {
        guard let changed = toolbarChanged else { return }
        if buttons != nil {
            toolbarOwner = ObjectIdentifier(owner)
        } else if toolbarOwner != ObjectIdentifier(owner) {
            return
        } else {
            toolbarOwner = nil
        }
        changed(buttons)
    }

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
