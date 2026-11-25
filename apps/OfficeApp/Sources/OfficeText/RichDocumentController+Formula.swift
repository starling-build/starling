import Foundation

/// W-TB-6: Layout > Formula.
extension RichDocumentController {
    /// The cell texts of the caret's table and the caret's place in it.
    func _formulaGrid(at paragraph: Int? = nil) -> TableFormula? {
        let at = paragraph ?? selection.focus.paragraph
        guard let id = document.paragraphs[at].cell?.table, let here = document.paragraphs[at].cell,
              let first = document.paragraphs(inTable: id).first, let last = document.paragraphs(inTable: id).last else { return nil }
        let range = first ..< last + 1
        let paras = document.paragraphs[range]
        let rows = (paras.compactMap { $0.cell.map { $0.row + $0.rowSpan } }.max() ?? 0)
        let cols = (paras.compactMap { $0.cell.map { $0.column + $0.span } }.max() ?? 0)
        var grid = Array(repeating: Array(repeating: "", count: cols), count: rows)
        for p in paras {
            guard let c = p.cell, c.row < rows, c.column < cols else { continue }
            grid[c.row][c.column] += grid[c.row][c.column].isEmpty ? p.text : "\n" + p.text
        }
        return TableFormula(grid: grid, row: here.row, column: here.column)
    }

    public var canInsertFormula: Bool {
        selection.focus.paragraph < document.paragraphs.count && document.paragraphs[selection.focus.paragraph].cell != nil
    }

    /// What Word offers first: SUM(ABOVE) when numbers stand above the cell, otherwise SUM(LEFT).
    public var suggestedFormula: String {
        guard let f = _formulaGrid() else { return "=SUM(ABOVE)" }
        return f.direction("ABOVE").isEmpty && !f.direction("LEFT").isEmpty ? "=SUM(LEFT)" : "=SUM(ABOVE)"
    }

    /// The text the formula would show in this cell, or nil when it cannot be worked out.
    public func formulaResult(_ formula: String, picture: String) -> String? {
        guard let f = _formulaGrid(), let v = f.evaluate(formula) else { return nil }
        return TableFormula.format(v, picture: picture)
    }

    /// Put `=formula \# "picture"` into the caret's cell as a real field showing its result, so Word can update it.
    @discardableResult
    public func insertFormula(_ formula: String, picture: String = "") -> Bool {
        guard canInsertFormula, let shown = formulaResult(formula, picture: picture) else { return false }
        var code = formula.trimmingWhitespace(newlines: true)
        if !code.hasPrefix("=") { code = "=" + code }
        let pic = picture.trimmingWhitespace(newlines: true)
        if !pic.isEmpty { code += " \\# \"\(pic)\"" }
        let at = selection.focus
        var style = document.paragraphs[at.paragraph].style(at: max(0, min(at.offset, document.paragraphs[at.paragraph].length) - 1))
        style.field = code
        edit {
            if hasSelection { deleteSelection() }
            let pos = selection.focus
            var p = document.paragraphs[pos.paragraph]
            p.insert(shown, at: pos.offset, runs: [Run(length: shown.utf16.count, style: style)])
            perform(.removeParagraphs(at: pos.paragraph, [document.paragraphs[pos.paragraph]]))
            perform(.insertParagraphs(at: pos.paragraph, [p]))
            _setCaret(RichPosition(paragraph: pos.paragraph, offset: pos.offset + shown.utf16.count))
        }
        return true
    }
}
