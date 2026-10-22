// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if !os(WASI)
/// Counts belong to the saved review snapshot. Missing upload evidence is not
/// zero words, and a held revision is a whole document, not newly written text.
struct SiteChapterWordCounts: Equatable {
    let saved: Int?
    let included: Int?
    let uploaded: Int?

    var summary: String {
        var parts: [String] = []
        if let saved { parts.append("Saved: \(saved) words") }
        if let included { parts.append("Included: \(included) words") }
        if let uploaded { parts.append("Last upload: \(uploaded) words") }
        return parts.joined(separator: " · ")
    }
}

struct SiteWritingProgress {
    struct Group: Equatable {
        let documents: Int
        let words: Int
        var summary: String { "\(documents) document\(documents == 1 ? "" : "s") · \(words) words" }
    }

    let unpublished: Group
    let held: Group
    let setAside: Group
    let included: Group

    init(review: SitePublishReview) {
        func group(_ slugs: [String], included: Bool = false) -> Group {
            let counts = slugs.compactMap { slug -> Int? in
                guard let words = review.wordCounts[slug] else { return nil }
                return included ? words.included : words.saved
            }
            return Group(documents: counts.count, words: counts.reduce(0, +))
        }
        unpublished = group(review.unpublished.map(\.slug))
        held = group(review.pages.filter { $0.heldDraft != nil }.map(\.slug))
        setAside = group(review.setAside.map(\.slug))
        included = group(review.pages.map(\.slug), included: true)
    }
}
#endif
