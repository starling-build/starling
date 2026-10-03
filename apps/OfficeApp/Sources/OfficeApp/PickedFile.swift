// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A file handed over as bytes rather than a path — the browser's picker
// gives nothing else — that has to cross a kind switch: Writer's picker
// gets a .pptx, Slides' gets a .docx, and OfficeRoot rebuilds the other
// shell by name. The bytes wait here for that shell's initState, which
// takes them if the name is the one it was built for.

import Foundation

enum PickedFile {
    nonisolated(unsafe) private static var pending: (name: String, data: Data)?

    static func hand(_ name: String, _ data: Data) { pending = (name, data) }

    /// The bytes handed over under `name`, once.
    static func take(_ name: String) -> Data? {
        guard let p = pending, p.name == name else { return nil }
        pending = nil
        return p.data
    }
}
