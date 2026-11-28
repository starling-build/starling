// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-ED-2: Word's Go To (Find and Replace > Go To, F5). What to type is Word's: a number goes
// there, "+n" / "-n" moves that many from where the caret is, and an empty box with Next or
// Previous goes to the next or previous one. A bookmark is gone to by its name.

public enum GoToWhat: String, CaseIterable, Sendable {
    case page = "Page", section = "Section", line = "Line", bookmark = "Bookmark", heading = "Heading", table = "Table"

    /// Word's prompt beside the box.
    public var prompt: String {
        switch self {
        case .page: return "Enter page number"
        case .section: return "Enter section number"
        case .line: return "Enter line number"
        case .bookmark: return "Enter bookmark name"
        case .heading: return "Enter heading number"
        case .table: return "Enter table number"
        }
    }
}

extension RichDocumentController {
    /// Where each item of `what` starts, in document order. `lines` is the layout's line starts
    /// with their pages (for Page and Line); the others come from the document alone.
    public func goToTargets(_ what: GoToWhat, lines: [(page: Int, at: RichPosition)]) -> [RichPosition] {
        let paras = document.paragraphs
        switch what {
        case .page:
            var out: [RichPosition] = []
            for l in lines where l.page > out.count {
                while out.count < l.page - 1 { out.append(out.last ?? l.at) }  // a page with no line of its own
                out.append(l.at)
            }
            return out
        case .line:
            return lines.map(\.at)
        case .section:
            var out = [RichPosition(paragraph: 0, offset: 0)]
            for (i, p) in paras.enumerated() where p.style.sectionXML != nil && i + 1 < paras.count {
                out.append(RichPosition(paragraph: i + 1, offset: 0))
            }
            return out
        case .heading:
            return paras.indices.filter { paras[$0].cell == nil && paras[$0].style.heading != nil }
                .map { RichPosition(paragraph: $0, offset: 0) }
        case .table:
            var out: [RichPosition] = []
            for (i, p) in paras.enumerated() where p.cell != nil && (i == 0 || paras[i - 1].cell == nil) {
                out.append(RichPosition(paragraph: i, offset: 0))
            }
            return out
        case .bookmark:
            return bookmarkEntries().map(\.start)
        }
    }

    /// Go to what `text` names (see the top of the file); `step` is +1 for Next, -1 for Previous
    /// when `text` is empty. Nil when it went; else Word's message.
    public func goTo(_ what: GoToWhat, _ text: String, step: Int = 0, lines: [(page: Int, at: RichPosition)] = []) -> String? {
        let typed = text.trimmingWhitespace()
        if what == .bookmark, !typed.isEmpty {
            return goToBookmark(typed) ? nil : "The bookmark does not exist."
        }
        let targets = goToTargets(what, lines: lines)
        let name = what.rawValue.lowercased()
        guard !targets.isEmpty else { return "The document has no \(name)s." }
        let here = document.clamped(selection.start)
        // The item the caret is in: the last that starts at or before it (0-based; -1 before the first).
        let current = (targets.lastIndex { $0 <= here }) ?? -1
        var index: Int
        if typed.isEmpty {
            guard step != 0 else { return "Type a \(name) number" }
            if step > 0 {
                guard let k = targets.firstIndex(where: { $0 > here }) else { return "There is no next \(name)." }
                index = k
            } else {
                guard let k = targets.lastIndex(where: { $0 < here }) else { return "There is no previous \(name)." }
                // Word: Previous from inside an item goes to that item's start first, then the one before.
                index = k
            }
        } else if let sign = typed.first, sign == "+" || sign == "-", let n = Int(typed.dropFirst()) {
            index = max(current, 0) + (sign == "+" ? n : -n)
        } else if let n = Int(typed) {
            index = n - 1
        } else if what == .bookmark {
            return "The bookmark does not exist."
        } else {
            return "Type a \(name) number"
        }
        index = min(max(index, 0), targets.count - 1)  // Word goes to the last (or first) one past either end
        moveTo(targets[index], extend: false)
        return nil
    }
}
