// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Find and Replace across a deck (S8): every text body in reading order —
// each slide's shapes front to back as they stack, tables included, then
// its notes — searched case-insensitively, as PowerPoint's Find does.

import Flutter
import FlutterSwiftBridge
import Foundation

/// One occurrence: where it is and what to select.
struct DeckMatch: Equatable {
    var slide: Int
    /// The text's place among the slide's bodies (shapes in order, then the
    /// notes), for ordering matches.
    var stop: Int
    /// The shape's deck id; nil for the notes.
    var shapeId: Int?
    var selection: RichSelection

    /// Reading order: slide, body, then position in the body.
    func isBefore(_ slide: Int, _ stop: Int, _ at: RichPosition) -> Bool {
        if self.slide != slide { return self.slide < slide }
        if self.stop != stop { return self.stop < stop }
        let p = selection.start
        return p.paragraph != at.paragraph ? p.paragraph < at.paragraph : p.offset < at.offset
    }
}

extension DeckController {
    /// The text bodies of slide `index` in reading order.
    func textStops(_ index: Int) -> [(shape: SlideShape?, controller: RichDocumentController)] {
        let slide = slides[index]
        return slide.shapes.compactMap { s in s.text.map { (s, $0) } } + [(nil, slide.notes)]
    }

    /// Every occurrence of `query` in the deck, in reading order.
    func matches(_ query: String) -> [DeckMatch] {
        guard !query.isEmpty else { return [] }
        var out: [DeckMatch] = []
        for i in slides.indices {
            for (stop, body) in textStops(i).enumerated() {
                for (p, para) in body.controller.document.paragraphs.enumerated() {
                    let text = para.text
                    var from = text.startIndex
                    while from < text.endIndex,
                          let r = text.findRange(of: query, caseSensitive: false, in: from ..< text.endIndex) {
                        out.append(DeckMatch(slide: i, stop: stop, shapeId: body.shape?.id, selection: RichSelection(
                            anchor: RichPosition(paragraph: p, offset: r.lowerBound.utf16Offset(in: text)),
                            focus: RichPosition(paragraph: p, offset: r.upperBound.utf16Offset(in: text)))))
                        from = r.upperBound
                    }
                }
            }
        }
        return out
    }
}
