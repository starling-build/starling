import Foundation
import OfficeText

/// One slide as the outline shows it: its title, then the lines of its body. A body line's level is 1 for a
/// first-level bullet, 2 for the next, and so on (the title is level 0).
struct OutlineEntry: Equatable {
    var title: String
    var body: [OutlineLine] = []
    /// The slide this row stands for (`Slide.id`); a row without one is a new slide. The outline's title paragraph
    /// carries it, so a row is matched to its slide by this and never by its position or its text.
    var slideId: Int? = nil
}

struct OutlineLine: Equatable {
    var level: Int
    var text: String
}

/// The Outline view's text: the deck as one document of titles and indented lines, and the way back.
enum Outline {
    static let indentPerLevel = 28.0
    /// A title paragraph's `divId` while it is in the outline: the slide it stands for.
    static let tagPrefix = "outline-slide-"

    static func document(_ entries: [OutlineEntry]) -> RichDocument {
        var paragraphs: [RichParagraph] = []
        func add(_ text: String, level: Int, tag: Int? = nil) {
            var style = RichParagraphStyle(spaceBefore: level == 0 ? 8 : 0, spaceAfter: 2, lineSpacing: 1.0, listLevel: level)
            style.indentLeft = Double(level) * indentPerLevel
            var char = CharStyle()
            char.bold = level == 0
            var p = RichParagraph(text: text, style: style)
            if level == 0, let id = tag { p.style.divId = Outline.tagPrefix + String(id) }
            p.runs = text.isEmpty ? [] : [Run(length: text.count, style: char)]
            paragraphs.append(p)
        }
        for e in entries {
            add(e.title, level: 0, tag: e.slideId)
            for line in e.body { add(line.text, level: max(1, line.level)) }
        }
        if paragraphs.isEmpty { add("", level: 0) }
        return RichDocument(paragraphs: paragraphs)
    }

    /// A level 0 paragraph starts a slide. The first paragraph always does.
    static func entries(from doc: RichDocument) -> [OutlineEntry] {
        var out: [OutlineEntry] = []
        for (i, p) in doc.paragraphs.enumerated() {
            let level = p.style.listLevel
            if i == 0 || level <= 0 {
                var e = OutlineEntry(title: p.text)
                if level <= 0, let d = p.style.divId, d.hasPrefix(tagPrefix) { e.slideId = Int(d.dropFirst(tagPrefix.count)) }
                out.append(e)
            } else {
                out[out.count - 1].body.append(OutlineLine(level: level, text: p.text))
            }
        }
        return out
    }

    enum Step: Equatable {
        case keep(old: Int)
        case edit(old: Int, new: Int)
        case insert(new: Int)
        case delete(old: Int)
    }

    /// How the slides in `old` become the rows in `new`, by slide id alone: a row with a known id is that slide (kept as it is,
    /// or edited), a row with no id, or an id already used by an earlier row (Enter copies a paragraph's tag), is a new slide, and
    /// a slide no row names is deleted. Steps come in the order of `new`, then the deletes.
    static func diff(old: [OutlineEntry], new: [OutlineEntry]) -> [Step] {
        var at: [Int: Int] = [:]
        for (i, e) in old.enumerated() { if let id = e.slideId { at[id] = i } }
        // When a tag was copied onto two rows, the row whose title still reads as the slide's own keeps it.
        var owner: [Int: Int] = [:]
        for (j, e) in new.enumerated() {
            guard let id = e.slideId, let o = at[id] else { continue }
            if let prev = owner[id] {
                if new[prev].title != old[o].title, e.title == old[o].title { owner[id] = j }
            } else { owner[id] = j }
        }
        var steps: [Step] = []
        var used = Set<Int>()
        for (j, e) in new.enumerated() {
            if let id = e.slideId, let o = at[id], owner[id] == j {
                used.insert(o)
                let same = old[o].title == e.title && old[o].body == e.body
                steps.append(same ? .keep(old: o) : .edit(old: o, new: j))
            } else {
                steps.append(.insert(new: j))
            }
        }
        for o in old.indices where !used.contains(o) { steps.append(.delete(old: o)) }
        return steps
    }
}
