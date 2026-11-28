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
            // The new rows go in before the old come out: a table that is the whole text never leaves it empty, which
            // would add a stray empty paragraph under the table (Slides' Custom Margins grew its frame 30 pt).
            perform(.insertParagraphs(at: range.lowerBound, paras))
            perform(.removeParagraphs(at: range.lowerBound + paras.count, old))
            if let widths = document.tableColumns[id] { perform(.setTableColumns(newID, old: nil, new: widths)) }
            if let style = document.tableStyles[id] {
                var first = style, second = style
                func cut<T>(_ d: [Int: T]) -> ([Int: T], [Int: T]) {
                    (d.filter { $0.key < line }, Dictionary(uniqueKeysWithValues: d.filter { $0.key >= line }.map { ($0.key - line, $0.value) }))
                }
                func cutSet(_ s: Set<Int>) -> (Set<Int>, Set<Int>) { (s.filter { $0 < line }, Set(s.filter { $0 >= line }.map { $0 - line })) }
                (first.rowHeights, second.rowHeights) = cut(style.rowHeights)
                (first.rowExceptions, second.rowExceptions) = cut(style.rowExceptions)
                (first.rowRevisionXML, second.rowRevisionXML) = cut(style.rowRevisionXML)
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

extension RichDocumentController {
    /// Word's Eraser: wiping an inner border merges the two cells it separates (when they line up edge to edge).
    /// Returns false for an outer border or cells that do not line up.
    @discardableResult
    public func eraseCellEdge(table: String, row: Int, column: Int, side: CellSide) -> Bool {
        let ps = document.paragraphs
        guard let here = ps.firstIndex(where: { $0.cell?.table == table && $0.cell?.row == row && $0.cell?.column == column }),
              let a = ps[here].cell else { return false }
        let r1 = a.row + a.rowSpan - 1, c1 = a.column + a.span - 1
        let nr: Int, nc: Int
        switch side {
        case .left: nr = a.row; nc = a.column - 1
        case .right: nr = a.row; nc = c1 + 1
        case .top: nr = a.row - 1; nc = a.column
        case .bottom: nr = r1 + 1; nc = a.column
        case .insideH, .insideV: return false
        }
        guard nr >= 0, nc >= 0, let other = ps.firstIndex(where: { q in
            guard let c = q.cell, c.table == table else { return false }
            return c.row <= nr && nr <= c.row + c.rowSpan - 1 && c.column <= nc && nc <= c.column + c.span - 1
        }), let b = ps[other].cell else { return false }
        let horizontal = side == .left || side == .right
        if horizontal ? (b.row != a.row || b.rowSpan != a.rowSpan) : (b.column != a.column || b.span != a.span) { return false }
        _setCaret(RichPosition(paragraph: min(here, other), offset: 0))
        moveTo(RichPosition(paragraph: max(here, other), offset: 0), extend: true)
        guard selection.block != nil else { return false }
        mergeCells()
        return true
    }

    /// Word's Draw Table, in a cell: a stroke across the cell splits it in two AT the stroke (a mostly horizontal stroke
    /// makes two rows, a mostly vertical one two columns). Outside a table the stroke makes a one-cell table.
    @discardableResult
    public func drawTable(in cell: DrawCell?, dx: Double, dy: Double) -> Bool {
        guard abs(dx) > 6 || abs(dy) > 6 else { return false }
        guard let cell else { insertTable(rows: 1, columns: 1); return true }
        guard let i = document.paragraphs.firstIndex(where: { $0.cell?.table == cell.table && $0.cell?.row == cell.row && $0.cell?.column == cell.column })
        else { return false }
        _setCaret(RichPosition(paragraph: i, offset: 0))
        if abs(dx) < abs(dy) {
            return splitCell(columns: 2, rows: 1, columnFraction: min(0.9, max(0.1, cell.fx)))
        }
        var done = false
        edit {
            done = splitCell(columns: 1, rows: 2)
            guard done else { return }
            let f = min(0.9, max(0.1, cell.fy)), h = max(2, cell.heightPoints)
            setTableStyle(of: cell.table) { $0.rowHeights[cell.row] = h * f; $0.rowHeights[cell.row + 1] = h * (1 - f) }
        }
        return done
    }
}

/// The cell a Draw Table stroke began in, and where in it (0...1 across and down) the stroke started.
public struct DrawCell: Sendable {
    public var table: String, row: Int, column: Int
    public var fx: Double, fy: Double
    /// The cell's height in points.
    public var heightPoints: Double
    public init(table: String, row: Int, column: Int, fx: Double = 0.5, fy: Double = 0.5, heightPoints: Double = 20) {
        self.table = table; self.row = row; self.column = column; self.fx = fx; self.fy = fy; self.heightPoints = heightPoints
    }
}
