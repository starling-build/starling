// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A document that belongs to something other than a file: a wiki page.
// Writer opens on it with everything it has — ribbon, find, styles,
// export — and the owner, not the file system, takes it back: Save hands
// the document to `save`, and the title bar's "Back to <owner>" (or
// Backstage's Close) calls `close`, through the usual unsaved-changes
// question first.

import Flutter

struct HostedDocument {
    /// What the title bar shows in place of a file name.
    let title: String
    let document: RichDocument
    /// The page it is laid out for; nil takes Writer's default.
    var pageSetup: PageSetup? = nil
    /// The owner's name, for "Back to wiki".
    let ownerName: String
    /// Store the document and its page setup; answers with nil, or the
    /// message to show.
    let save: (RichDocument, PageSetup, @escaping (String?) -> Void) -> Void
    /// Leave the document; the owner shows whatever it shows next.
    let close: () -> Void
}
