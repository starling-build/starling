import Foundation
import OfficeText

/// One slide as the outline shows it: its title, then the lines of its body. A body line's level is 1 for a
/// first-level bullet, 2 for the next, and so on (the title is level 0).
struct OutlineEntry: Equatable {
    var title: String
    var body: [OutlineLine] = []
}

struct OutlineLine: Equatable {
    var level: Int
    var text: String
}

/// The Outline view's text: the deck as one document of titles and indented lines, and the way back.
enum Outline {
    static let indentPerLevel = 28.0

    static func document(_ entries: [OutlineEntry]) -> RichDocument {
        var paragraphs: [RichParagraph] = []
        func add(_ text: String, level: Int) {
            var style = RichParagraphStyle(spaceBefore: level == 0 ? 8 : 0, spaceAfter: 2, lineSpacing: 1.0, listLevel: level)
            style.indentLeft = Double(level) * indentPerLevel
            var char = CharStyle()
            char.bold = level == 0
            var p = RichParagraph(text: text, style: style)
            p.runs = text.isEmpty ? [] : [Run(length: text.count, style: char)]
            paragraphs.append(p)
        }
        for e in entries {
            add(e.title, level: 0)
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
                out.append(OutlineEntry(title: p.text))
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

    /// How the slides in `old` become the entries in `new`: whole entries that did not change are matched first
    /// (longest common run), and what lies between two matches pairs up in order as edits, the rest as inserts or deletes.
    static func diff(old: [OutlineEntry], new: [OutlineEntry]) -> [Step] {
        let n = old.count, m = new.count
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0, m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = old[i] == new[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        var steps: [Step] = []
        var gapOld: [Int] = [], gapNew: [Int] = []
        // Inside a stretch of changes, a slide is still the same slide when its title or its (non-empty) body is unchanged;
        // the rest pair one to one when they are alone between two such slides, else they are inserted and deleted.
        func same(_ o: OutlineEntry, _ n: OutlineEntry) -> Bool {
            o.title == n.title || (!o.body.isEmpty && o.body == n.body)
        }
        func flush() {
            let go = gapOld, gn = gapNew
            gapOld = []; gapNew = []
            let a = go.count, b = gn.count
            var t = [[Int]](repeating: [Int](repeating: 0, count: b + 1), count: a + 1)
            if a > 0, b > 0 {
                for x in stride(from: a - 1, through: 0, by: -1) {
                    for y in stride(from: b - 1, through: 0, by: -1) {
                        t[x][y] = same(old[go[x]], new[gn[y]]) ? t[x + 1][y + 1] + 1 : max(t[x + 1][y], t[x][y + 1])
                    }
                }
            }
            var subOld: [Int] = [], subNew: [Int] = []
            func rest() {
                if subOld.count == subNew.count {
                    for k in 0 ..< subOld.count { steps.append(.edit(old: subOld[k], new: subNew[k])) }
                } else {
                    for k in subNew { steps.append(.insert(new: k)) }
                    for k in subOld { steps.append(.delete(old: k)) }
                }
                subOld = []; subNew = []
            }
            var x = 0, y = 0
            while x < a || y < b {
                if x < a, y < b, same(old[go[x]], new[gn[y]]), t[x][y] == t[x + 1][y + 1] + 1 {
                    rest(); steps.append(.edit(old: go[x], new: gn[y])); x += 1; y += 1
                } else if y >= b || (x < a && t[x + 1][y] >= t[x][y + 1]) {
                    subOld.append(go[x]); x += 1
                } else {
                    subNew.append(gn[y]); y += 1
                }
            }
            rest()
        }
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, old[i] == new[j] {
                flush(); steps.append(.keep(old: i)); i += 1; j += 1
            } else if j >= m || (i < n && lcs[i + 1][j] >= lcs[i][j + 1]) {
                gapOld.append(i); i += 1
            } else {
                gapNew.append(j); j += 1
            }
        }
        flush()
        return steps
    }
}
