// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// AutoComplete from the column (X-CE-1): typing the start of a word that is already in the column offers the rest,
// and Alt+Down lists the column's words. Excel looks at the unbroken run of cells above and below the one being
// edited, text only.

extension WorkbookController {
    /// The distinct text typed into the run of filled cells above and below `cell` (blank cell ends the run), in sheet order.
    func columnWords(at cell: CellAddress) -> [String] {
        func word(_ row: Int) -> String? {
            guard row >= 0, row < CellAddress.maxRows, let c = sheet.cells[CellAddress(row: row, col: cell.col)] else { return nil }
            if c.value.isEmpty { return nil }
            if c.formula == nil, case .text(let t) = c.value, !t.isEmpty { return t }
            return ""   // filled, but not text: the run goes on without offering it
        }
        var top = cell.row, bottom = cell.row
        while word(top - 1) != nil { top -= 1 }
        while word(bottom + 1) != nil { bottom += 1 }
        var seen = Set<String>(), out: [String] = []
        for r in top ... bottom where r != cell.row {
            if let w = word(r), !w.isEmpty, seen.insert(w.lowercased()).inserted { out.append(w) }
        }
        return out
    }

    /// The column word that continues what is typed, nil when none does or the entry is a formula or a number.
    func columnSuggestion(for typed: String, at cell: CellAddress) -> String? {
        guard !typed.isEmpty, typed.first != "=", typed.contains(where: { $0.isLetter }) else { return nil }
        let low = typed.lowercased()
        return columnWords(at: cell).first { $0.count > typed.count && $0.lowercased().hasPrefix(low) }
    }
}
