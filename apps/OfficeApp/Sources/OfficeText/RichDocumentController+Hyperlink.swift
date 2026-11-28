// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// Insert Hyperlink (U-LINK-1): address or in-document target, display
/// text and screen tip, applied as ONE undo step.

/// Somewhere in the document a link can point.
public struct LinkTarget: Equatable {
    public enum Kind { case bookmark, heading }
    public var kind: Kind
    /// Bookmark name (a heading's own bookmark when it has one, else nil:
    /// one is made when the link is applied).
    public var bookmark: String?
    public var title: String
    public var paragraph: Int
    public var level: Int
}

extension RichDocumentController {
    /// The bookmarks (Word hides those starting with "_") and the headings.
    public func linkTargets() -> [LinkTarget] {
        var marks: [LinkTarget] = [], heads: [LinkTarget] = []
        for (i, p) in document.paragraphs.enumerated() {
            for name in p.bookmarks where !name.hasPrefix("_") {
                marks.append(LinkTarget(kind: .bookmark, bookmark: name, title: name, paragraph: i, level: 0))
            }
            if let level = p.style.heading, !p.text.isEmpty {
                let own = p.bookmarks.first
                heads.append(LinkTarget(kind: .heading, bookmark: own, title: p.text, paragraph: i, level: level))
            }
        }
        return marks + heads
    }

    /// The target an in-document link ("#name") goes to, so editing the link opens on it.
    public static func linkTargetIndex(of link: String, in targets: [LinkTarget]) -> Int? {
        guard link.hasPrefix("#"), link.count > 1 else { return nil }
        let name = String(link.dropFirst())
        return targets.firstIndex { $0.bookmark == name }
    }

    /// The link under the caret (or selection): address, tip, and the
    /// text of the whole linked stretch.
    public var currentLinkTip: String? { currentCharStyle.linkTip }

    /// Link the selection (or insert the link where the caret is).
    /// `address` is a URL, or "#name" for a bookmark; `target` names a heading or bookmark
    /// instead, making the heading's bookmark when it has none. `text` replaces
    /// the selected text when it differs. One undo undoes all of it.
    /// Returns false when there is nothing to link to.
    @discardableResult
    public func applyHyperlink(address: String, target: LinkTarget? = nil, text: String? = nil, tip: String? = nil) -> Bool {
        var address = address
        let tip = (tip?.isEmpty ?? true) ? nil : tip
        guard !address.isEmpty || target != nil else { return false }
        edit {
            if let target {
                var name = target.bookmark
                if name == nil, target.paragraph < document.paragraphs.count {
                    var taken = Set(document.paragraphs.flatMap { $0.bookmarks })
                    var n = 0
                    var candidate = "_Heading\(target.paragraph)"
                    while taken.contains(candidate) { n += 1; candidate = "_Heading\(target.paragraph)_\(n)" }
                    taken.insert(candidate)
                    var p = document.paragraphs[target.paragraph]
                    p.bookmarks.append(candidate)
                    // A range over the heading's text (as Word's _Toc bookmarks), so a REF to it shows the heading.
                    let used = document.paragraphs.flatMap { $0.bookmarkMarkers.map(\.id) }.compactMap { Int($0) }
                    let id = String(max(300_000, (used.max() ?? 0) + 1))
                    p.bookmarkMarkers.append(RichBookmarkMarker(id: id, name: candidate, offset: 0))
                    p.bookmarkMarkers.append(RichBookmarkMarker(id: id, offset: p.length))
                    perform(.restoreParagraphs(target.paragraph, count: 1, [p]))
                    name = candidate
                }
                address = "#" + (name ?? "")
            }
            let shown = (text?.isEmpty ?? true) ? nil : text
            if selection.isCollapsed {
                let pos = selection.focus
                insertText(shown ?? (target?.title ?? address))
                selection = RichSelection(anchor: pos, focus: selection.focus)
            } else if let shown, shown != selectedText {
                insertText(shown)   // replaces the selection
                let end = selection.focus
                let start = RichPosition(paragraph: end.paragraph, offset: max(0, end.offset - shown.utf16.count))
                selection = RichSelection(anchor: start, focus: end)
            }
            applyCharStyle { $0.link = address; $0.linkTip = tip }
            selection = RichSelection(caret: selection.focus)
        }
        return true
    }
}
