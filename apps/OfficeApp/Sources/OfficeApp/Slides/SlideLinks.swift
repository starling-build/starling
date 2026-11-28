// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// S-TX-4: what a Slides link means and where it goes. A link is kept as a string: "slide:<part>" (a slide of
// this deck, "new:<id>" for one added here), "action:ppaction://hlinkshowjump?jump=..." (first, last, next,
// previous slide, end show), or an address (https:, mailto:, a file).

import Flutter

enum SlideLinks {
    /// The jumps PowerPoint lists over the slides in Place in This Document.
    static let relativePlaces: [HyperlinkPlace] = [
        HyperlinkPlace(id: "action:ppaction://hlinkshowjump?jump=firstslide", title: "First Slide", kind: "Jump"),
        HyperlinkPlace(id: "action:ppaction://hlinkshowjump?jump=lastslide", title: "Last Slide", kind: "Jump"),
        HyperlinkPlace(id: "action:ppaction://hlinkshowjump?jump=nextslide", title: "Next Slide", kind: "Jump"),
        HyperlinkPlace(id: "action:ppaction://hlinkshowjump?jump=previousslide", title: "Previous Slide", kind: "Jump"),
    ]

    /// The text a link to a slide shows when there is none: the slide's title, else "Slide N" ("Slide 3: Plans" → "Plans").
    static func shownName(_ targetTitle: String) -> String {
        guard let colon = targetTitle.firstIndex(of: ":") else { return targetTitle }
        let rest = String(targetTitle[targetTitle.index(after: colon)...]).trimmingWhitespace()
        return rest.isEmpty ? targetTitle : rest
    }

    /// The dialog's place id for a link that points into the deck (nil for an address).
    static func place(of link: String) -> String? {
        if link.hasPrefix("slide:") { return String(link.dropFirst(6)) }
        if relativePlaces.contains(where: { $0.id == link }) { return link }
        return nil
    }

    /// The slide a link goes to from slide `from`, in the editor (no show order); nil when it is not a jump in the deck.
    static func target(_ link: String, from: Int, in deck: DeckController) -> Int? {
        let n = deck.slides.count
        guard n > 0 else { return nil }
        if link.hasPrefix("slide:") {
            let key = String(link.dropFirst(6))
            return deck.slides.firstIndex { ($0.sourcePart ?? "new:\($0.id)") == key }
        }
        guard link.hasPrefix("action:") else { return nil }
        if link.hasSuffix("jump=firstslide") { return 0 }
        if link.hasSuffix("jump=lastslide") { return n - 1 }
        if link.hasSuffix("jump=nextslide") { return min(from + 1, n - 1) }
        if link.hasSuffix("jump=previousslide") { return max(from - 1, 0) }
        return nil
    }

    /// An address the system opens (web page, e-mail); a show action or a slide jump is not one.
    static func isAddress(_ link: String) -> Bool {
        let l = link.lowercased()
        return l.hasPrefix("https://") || l.hasPrefix("http://") || l.hasPrefix("mailto:")
    }

    /// Follows a link in the editor (Ctrl/Cmd+click, Open Link): a slide jump selects that slide, an address opens.
    /// False when the link goes nowhere this can follow (a deleted slide, a program to run).
    @discardableResult
    static func follow(_ link: String, in deck: DeckController, openURL: (String) -> Void) -> Bool {
        if let i = target(link, from: deck.current, in: deck) { deck.selectSlide(i); return true }
        guard isAddress(link) else { return false }
        openURL(link)
        return true
    }
}
