// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import Foundation

/// A replacement is prepared without writing. The original bytes are checked
/// again when applying it so a preview cannot overwrite intervening edits.
struct SiteRevision {
    let slug: String
    let original: SitePage
    let replacement: SitePage
    let originalBytes: Data
    let retained: Int
    let changed: Int
    let added: Int
    let removed: Int
    #if !os(WASI)
    /// Local owner storage at review time, so an import cannot cross from a
    /// held draft into release files when another window includes the draft.
    var storageID: String? = nil
    #endif

    var summary: String {
        "\(retained) paragraph links retained; \(changed) matched paragraphs changed; \(added) new, \(removed) removed or unmatched."
    }

    init(slug: String, original: SitePage, incoming: SitePage, originalBytes: Data) {
        self.slug = slug
        self.original = original
        self.originalBytes = originalBytes
        let old = original.document.paragraphs
        let fresh = incoming.document.paragraphs
        let oldIDs = Dictionary(grouping: old.indices.filter { old[$0].id != 0 }, by: { old[$0].id })
        let newIDs = Dictionary(grouping: fresh.indices.filter { fresh[$0].id != 0 }, by: { fresh[$0].id })
        let oldText = Dictionary(grouping: old.indices.filter { !old[$0].text.trimmingWhitespace().isEmpty }, by: { old[$0].text })
        let newText = Dictionary(grouping: fresh.indices.filter { !fresh[$0].text.trimmingWhitespace().isEmpty }, by: { fresh[$0].text })
        var matches: [Int: Int] = [:]
        var used = Set<Int>()
        // Word's persistent paraId is the strongest identity, including when
        // the author changes the paragraph. Duplicate IDs are never trusted.
        for (id, indices) in newIDs where indices.count == 1 {
            if let prior = oldIDs[id], prior.count == 1 {
                matches[indices[0]] = prior[0]
                used.insert(prior[0])
            }
        }
        // Exporters may drop paraId. Recover only unambiguous exact text,
        // including moves; never guess by paragraph position or fuzzy text.
        for (text, indices) in newText where indices.count == 1 {
            let index = indices[0]
            if matches[index] == nil, let prior = oldText[text], prior.count == 1,
               !used.contains(prior[0]), old[prior[0]].id != 0, oldIDs[old[prior[0]].id]?.count == 1 {
                matches[index] = prior[0]
                used.insert(prior[0])
            }
        }
        var document = incoming.document
        // Retired links must never accidentally refer to a new paragraph.
        var taken = Set(old.map(\.id))
        var changed = 0
        for i in document.paragraphs.indices {
            if let prior = matches[i] {
                document.paragraphs[i].id = old[prior].id
                if document.paragraphs[i] != old[prior] { changed += 1 }
            } else {
                var id = fresh[i].id
                if id == 0 || taken.contains(id) || newIDs[id]?.count != 1 {
                    repeat { id = RichParagraph.freshID() } while taken.contains(id)
                }
                document.paragraphs[i].id = id
            }
            taken.insert(document.paragraphs[i].id)
        }
        replacement = SitePage(document: document, pageSetup: incoming.pageSetup)
        retained = matches.count
        self.changed = changed
        added = fresh.count - matches.count
        removed = old.count - used.count
    }
}
