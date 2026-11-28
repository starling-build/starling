// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A file handed over as bytes rather than a path — the browser's picker
// gives nothing else — that has to cross a kind switch: Writer's picker
// gets a .pptx, Slides' gets a .docx, and OfficeRoot rebuilds the other
// shell by name. The bytes wait here for that shell's initState, which
// takes them if the name is the one it was built for.

import Foundation
#if os(WASI)
import FlutterWeb
#endif

enum PickedFile {
    nonisolated(unsafe) private static var pending: (name: String, data: Data, recovered: Bool, handle: Int?)?

    /// `recovered`: a browser tab's recovery copy of an unsaved document, which the next app opens unsaved.
    /// `handle`: the page's handle on the picked file, so the next app saves back into it.
    static func hand(_ name: String, _ data: Data, recovered: Bool = false, handle: Int? = nil) {
        pending = (name, data, recovered, handle)
    }

    /// The handle that came with the bytes `take` last gave out (nil when none came).
    nonisolated(unsafe) private(set) static var takenHandle: Int?

    /// The bytes handed over under `name` as a recovery copy, once; nil for an ordinary hand-over.
    static func takeRecovered(_ name: String) -> Data? {
        guard let p = pending, p.name == name, p.recovered else { return nil }
        pending = nil
        return p.data
    }

    /// The bytes handed over under `name`, once.
    static func take(_ name: String) -> Data? {
        takenHandle = nil
        if let p = pending, p.name == name {
            pending = nil
            takenHandle = p.handle
            return p.data
        }
        #if os(WASI)
        // A web app can supply its opening example before Swift mounts.
        // Consume it once, just like a file picked in another Office app.
        return WebFiles.startupFiles.removeValue(forKey: name)
        #else
        return nil
        #endif
    }
}
