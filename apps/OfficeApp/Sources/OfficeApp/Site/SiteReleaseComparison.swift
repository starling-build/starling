// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import Foundation

#if !os(WASI)
/// A read-only comparison of a saved draft with the document actually included
/// in a recorded upload. It never changes paragraph IDs or restores old files.
struct SiteReleaseComparison {
    enum Kind: String {
        case edited = "Text changed"
        case details = "Paragraph details changed"
        case added = "Added paragraph"
        case removed = "Removed paragraph"
    }

    struct Passage {
        let kind: Kind
        let before: String?
        let after: String?
        /// Only unique, nonzero identities in the current draft are navigable.
        let paragraphID: UInt32?
        let oldNumber: Int?
        let newNumber: Int?
    }

    let previousTitle: String?
    let currentTitle: String?
    let passages: [Passage]
    let orderChanged: Bool
    let documentDetailsChanged: Bool
    let pageSetupChanged: Bool

    var summary: String {
        let edited = passages.filter { $0.kind == .edited }.count
        let details = passages.filter { $0.kind == .details }.count
        let added = passages.filter { $0.kind == .added }.count
        let removed = passages.filter { $0.kind == .removed }.count
        return "Paragraph changes: \(edited) edited, \(added) added, \(removed) removed; \(details) with other details changed."
    }

    init(previous: SitePage?, current: SitePage?, previousTitle: String?, currentTitle: String?) {
        self.previousTitle = previousTitle
        self.currentTitle = currentTitle
        let old = previous?.document.paragraphs ?? []
        let fresh = current?.document.paragraphs ?? []
        if let previous, let current {
            var oldDetails = previous.document
            var newDetails = current.document
            oldDetails.paragraphs = []
            newDetails.paragraphs = []
            documentDetailsChanged = oldDetails != newDetails
            pageSetupChanged = previous.pageSetup != current.pageSetup
        } else {
            documentDetailsChanged = false
            pageSetupChanged = false
        }
        // Identical sequences need no identity inference, including legacy
        // documents with repeated text, empty paragraphs and no paragraph IDs.
        if old == fresh {
            passages = []
            orderChanged = false
            return
        }
        let oldIDs = Dictionary(grouping: old.indices.filter { old[$0].id != 0 }, by: { old[$0].id })
        let newIDs = Dictionary(grouping: fresh.indices.filter { fresh[$0].id != 0 }, by: { fresh[$0].id })
        var matches: [Int: Int] = [:]
        var used = Set<Int>()
        for (id, indices) in newIDs where indices.count == 1 {
            if let prior = oldIDs[id], prior.count == 1 {
                matches[indices[0]] = prior[0]
                used.insert(prior[0])
            }
        }
        // Imports can replace paragraph identities. Match exact, unique text
        // only; repeated or edited unidentified passages remain additions and
        // removals rather than suggesting a relationship we cannot establish.
        let oldText = Dictionary(grouping: old.indices.filter { !old[$0].text.isEmpty }, by: { old[$0].text })
        let newText = Dictionary(grouping: fresh.indices.filter { !fresh[$0].text.isEmpty }, by: { fresh[$0].text })
        for (text, indices) in newText where indices.count == 1 {
            let index = indices[0]
            if matches[index] == nil, let prior = oldText[text], prior.count == 1, !used.contains(prior[0]) {
                matches[index] = prior[0]
                used.insert(prior[0])
            }
        }
        var changes: [Passage] = []
        var lastOldIndex = -1
        var reordered = false
        for index in fresh.indices {
            let paragraph = fresh[index]
            let id = paragraph.id != 0 && newIDs[paragraph.id]?.count == 1 ? paragraph.id : nil
            if let prior = matches[index] {
                if prior < lastOldIndex { reordered = true }
                lastOldIndex = prior
                var comparable = paragraph
                comparable.id = old[prior].id
                if comparable != old[prior] {
                    changes.append(Passage(kind: paragraph.text == old[prior].text ? .details : .edited,
                                           before: old[prior].text, after: paragraph.text,
                                           paragraphID: id, oldNumber: prior + 1, newNumber: index + 1))
                }
            } else {
                changes.append(Passage(kind: .added, before: nil, after: paragraph.text,
                                       paragraphID: id, oldNumber: nil, newNumber: index + 1))
            }
        }
        for index in old.indices where !used.contains(index) {
            changes.append(Passage(kind: .removed, before: old[index].text, after: nil,
                                   paragraphID: nil, oldNumber: index + 1, newNumber: nil))
        }
        passages = changes
        orderChanged = reordered
    }
}
#endif
