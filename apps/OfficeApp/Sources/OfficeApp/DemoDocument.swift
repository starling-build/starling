// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import Foundation

/// The Phase 0 perf document: `pages` pages of prose with a heading per
/// page, a list every few paragraphs, and some inline formatting so the run
/// machinery is exercised. Deterministic, so two runs compare.
enum DemoDocument {
    private static let words = """
    lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor \
    incididunt ut labore et dolore magna aliqua ut enim ad minim veniam quis \
    nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat \
    duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore \
    eu fugiat nulla pariatur excepteur sint occaecat cupidatat non proident sunt \
    in culpa qui officia deserunt mollit anim id est laborum
    """.split(separator: " ").map(String.init)

    static func make(pages: Int) -> RichDocument {
        var paragraphs: [RichParagraph] = []
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) & 0x7FFFFFFF)
        }
        func sentence(_ n: Int) -> String {
            var out: [String] = []
            for i in 0 ..< n {
                var w = words[next() % words.count]
                if i == 0 { w = w.prefix(1).uppercased() + w.dropFirst() }
                out.append(w)
            }
            return out.joined(separator: " ") + "."
        }
        paragraphs.append(RichParagraph(text: "Office — Phase 0 performance document",
                                        style: RichParagraphStyle(heading: 1)))
        paragraphs.append(RichParagraph(text: "\(pages) pages, generated. Type anywhere; every keystroke must lay out one paragraph. This intro is a single run and long enough to wrap onto several lines so that word wrapping can be compared against the multi-run paragraphs below it, which carry bold and italic runs."))
        for page in 1 ... max(1, pages) {
            paragraphs.append(RichParagraph(text: "Section \(page): \(sentence(3 + next() % 4).dropLast())",
                                            style: RichParagraphStyle(heading: 2)))
            for k in 0 ..< 5 {
                let sentences = 3 + next() % 4
                var text = ""
                for s in 0 ..< sentences {
                    text += sentence(8 + next() % 12)
                    if s + 1 < sentences { text += " " }
                }
                var p = RichParagraph(text: text)
                // Bold the first clause, italicise a word in the middle.
                if let dot = text.utf16.firstIndex(of: 0x2C) ?? text.utf16.firstIndex(of: 0x2E) {
                    let end = text.utf16.distance(from: text.utf16.startIndex, to: dot)
                    p.applyStyle(0 ..< end) { $0.bold = true }
                }
                let mid = p.length / 2
                let r = p.wordRange(at: mid)
                p.applyStyle(r) { $0.italic = true }
                paragraphs.append(p)
                if k == 2 {
                    for item in 0 ..< 3 {
                        paragraphs.append(RichParagraph(text: sentence(4 + next() % 5),
                                                        style: RichParagraphStyle(list: item == 2 ? .numbered : .bullet)))
                    }
                }
            }
        }
        var doc = RichDocument(paragraphs: paragraphs)
        doc.styles = OfficeStyles.sheet
        return doc
    }
}
