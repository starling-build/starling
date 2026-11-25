// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-LK-1: Insert Hyperlink (Ctrl+K), on the shared dialog.
import Flutter
import FlutterSwiftBridge

/// What a typed address means: a place in the workbook, a mail address, or a web address.
enum HyperlinkInput {
    static func link(_ text: String, place: Bool) -> SheetLink? {
        let t = text.trimmingWhitespace()
        guard !t.isEmpty else { return nil }
        if place { return .place(t) }
        if t.containsSubstring("://") || t.hasPrefix("mailto:") || t.hasPrefix("tel:") { return .url(t) }
        if t.containsSubstring("@"), !t.containsSubstring("/") { return .url("mailto:" + t) }
        return .url("https://" + t)
    }
    /// The text of a link, to put back in the field when editing.
    static func text(_ link: SheetLink?) -> (text: String, place: Bool) {
        switch link {
        case .url(let u)?: return (u, false)
        case .place(let p)?: return (p, true)
        case nil: return ("", false)
        }
    }
}

extension WorkbookController {
    /// The shared Insert Hyperlink dialog's hooks for the selection: places are the sheets
    /// (their first cell) and the defined names; an address typed as "#Sheet2!B5" is a place too.
    func hyperlinkHooks(flash: @escaping (String) -> Void) -> HyperlinkHooks {
        let sel = selection
        let cur = link(at: active)
        var places: [HyperlinkPlace] = book.sheets.filter { !$0.hidden }.map {
            HyperlinkPlace(id: Formula.quoteSheet($0.name) + "!A1", title: $0.name + "!A1", kind: "Cell")
        }
        places += book.names.keys.sorted().map { HyperlinkPlace(id: $0, title: $0, kind: "Name") }
        let shown = HyperlinkInput.text(cur)
        var h = HyperlinkHooks(apply: { [weak self] address, place, _, tip in
            guard let self else { return "" }
            let raw = place ?? (address.hasPrefix("#") ? String(address.dropFirst()) : address)
            guard let link = HyperlinkInput.link(raw, place: place != nil || address.hasPrefix("#")) else { return "Type an address" }
            self.setLink(sel, link, tip: tip.isEmpty ? nil : tip)
            flash("Linked")
            return ""
        })
        h.placesLabel = "Cell or name"
        h.places = places
        h.hasDisplayText = false
        h.address = shown.place ? "#" + shown.text : shown.text
        h.canRemove = cur != nil
        h.remove = { [weak self] in self?.removeLink(sel) }
        return h
    }
}
