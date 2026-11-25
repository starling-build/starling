import Foundation

extension RichDocumentController {
    /// Table > Split Table: the caret's row and the rows below it become a table of their own, with an empty
    /// paragraph between the two (Word's Ctrl+Shift+Enter). In the first row the empty paragraph goes above the table.
    /// Not offered when a cell merged downward crosses the line.
    public var canSplitTable: Bool {
        guard let here = currentCell else { return false }
        return !document.paragraphs.contains { p in
            guard let c = p.cell, c.table == here.table else { return false }
            return c.row < here.row && c.row + c.rowSpan > here.row
        }
    }

    @discardableResult
    public func splitTable() -> Bool {
        guard canSplitTable, let here = currentCell, let range = currentTableRange else { return false }
        let id = here.table, line = here.row
        edit {
            if line == 0 {
                perform(.insertParagraphs(at: range.lowerBound, [RichParagraph()]))
                _setCaret(RichPosition(paragraph: range.lowerBound + 1, offset: 0))
                return
            }
            let newID = UUID().uuidString
            var paras = Array(document.paragraphs[range])
            let old = paras
            var out: [RichParagraph] = [], tail: [RichParagraph] = []
            for var p in paras {
                guard var c = p.cell else { out.append(p); continue }
                if c.row >= line { c.table = newID; c.row -= line; p.cell = c; tail.append(p) } else { out.append(p) }
            }
            paras = out + [RichParagraph()] + tail
            let caretAt = out.count + 1
            perform(.removeParagraphs(at: range.lowerBound, old))
            perform(.insertParagraphs(at: range.lowerBound, paras))
            if let widths = document.tableColumns[id] { perform(.setTableColumns(newID, old: nil, new: widths)) }
            if let style = document.tableStyles[id] {
                var first = style, second = style
                func cut<T>(_ d: [Int: T]) -> ([Int: T], [Int: T]) {
                    (d.filter { $0.key < line }, Dictionary(uniqueKeysWithValues: d.filter { $0.key >= line }.map { ($0.key - line, $0.value) }))
                }
                func cutSet(_ s: Set<Int>) -> (Set<Int>, Set<Int>) { (s.filter { $0 < line }, Set(s.filter { $0 >= line }.map { $0 - line })) }
                (first.rowHeights, second.rowHeights) = cut(style.rowHeights)
                (first.rowExceptions, second.rowExceptions) = cut(style.rowExceptions)
                (first.rowsGridBefore, second.rowsGridBefore) = cut(style.rowsGridBefore)
                (first.rowsExactHeight, second.rowsExactHeight) = cutSet(style.rowsExactHeight)
                (first.rowsCantSplit, second.rowsCantSplit) = cutSet(style.rowsCantSplit)
                (first.rowsUnspaced, second.rowsUnspaced) = cutSet(style.rowsUnspaced)
                second.headerRow = false
                if style.headerRow, style.headerRowCount > line { first.headerRowCount = line }
                perform(.setTableStyle(id, old: style, new: first))
                perform(.setTableStyle(newID, old: nil, new: second))
            }
            _setCaret(RichPosition(paragraph: range.lowerBound + caretAt, offset: 0))
        }
        return true
    }
}
