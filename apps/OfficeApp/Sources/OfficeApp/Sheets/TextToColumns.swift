// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-6b: Data → Text to Columns (delimited). Each cell of one column is split at the chosen
// separators and the pieces are written to the cells to its right. One undo step.

import Foundation

struct TextSplitOptions: Equatable {
    var tab = false, semicolon = false, comma = true, space = false
    var other: Character? = nil
    /// Two separators in a row count as one.
    var consecutiveAsOne = false
    /// Text between a pair of these is kept whole, even if it holds separators.
    var qualifier: Character? = "\""

    var separators: Set<Character> {
        var s = Set<Character>()
        if tab { s.insert("\t") }
        if semicolon { s.insert(";") }
        if comma { s.insert(",") }
        if space { s.insert(" ") }
        if let o = other { s.insert(o) }
        return s
    }
}

enum TextToColumnsProblem: Equatable {
    case oneColumn, noSeparator, wouldOverwrite, mergedCells
    var message: String {
        switch self {
        case .oneColumn: return "Select cells in one column to split."
        case .noSeparator: return "Choose at least one separator."
        case .wouldOverwrite: return "There is already data to the right. Clear it or choose fewer separators."
        case .mergedCells: return "Splitting needs cells of the same size. Unmerge the merged cells first."
        }
    }
}

enum TextSplitter {
    /// Split one line of text. Pure, so it is easy to test.
    static func split(_ text: String, _ o: TextSplitOptions) -> [String] {
        let seps = o.separators
        var out: [String] = [], cur = "", inQuote = false, wasSep = false
        for ch in text {
            if let q = o.qualifier, ch == q { inQuote.toggle(); wasSep = false; continue }
            if !inQuote, seps.contains(ch) {
                if !(o.consecutiveAsOne && wasSep) { out.append(cur); cur = "" }
                wasSep = true
                continue
            }
            wasSep = false
            cur.append(ch)
        }
        out.append(cur)
        return out
    }
}

extension WorkbookController {
    /// Split each cell of `range` (one column). Returns the number of columns used, or the problem.
    func textToColumns(_ range: CellRange, options: TextSplitOptions) -> (columns: Int?, problem: TextToColumnsProblem?) {
        guard range.left == range.right else { return (nil, .oneColumn) }
        guard !options.separators.isEmpty else { return (nil, .noSeparator) }
        if sheet.merges.contains(where: { $0.intersects(range) }) { return (nil, .mergedCells) }
        var rows: [(Int, [String])] = []
        for r in range.top ... range.bottom {
            let a = CellAddress(row: r, col: range.left)
            guard sheet.cells[a] != nil else { continue }
            let code = book.style(sheet.cells[a]?.style ?? sheet.defaultStyle(at: a)).numberFormat
            let text = NumberFormat.display(sheet.value(a), code, width: 255).text
            rows.append((r, TextSplitter.split(text, options)))
        }
        let width = rows.map { $0.1.count }.max() ?? 1
        guard width > 1 else { return (1, nil) }
        var items: [(CellAddress, String)] = []
        for (r, parts) in rows {
            for (i, p) in parts.enumerated() {
                let a = CellAddress(row: r, col: range.left + i)
                if i > 0, let c = sheet.cells[a], !c.input.isEmpty { return (nil, .wouldOverwrite) }
                items.append((a, p))
            }
        }
        setInputs(items)
        return (width, nil)
    }
}
