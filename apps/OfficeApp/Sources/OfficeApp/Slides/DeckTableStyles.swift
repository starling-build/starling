// Drawing a table in one of PowerPoint's built-in styles (Themed, Light, Medium, Dark: every family in every colour)
// from the style's own definition, so the gallery can offer them all. The table keeps only the style's id: its colours are
// painted from the definition and the theme, never written as direct fills (a fill the user shaded stays theirs).
import Flutter
import FlutterSwiftBridge
import Foundation
import OfficeText

extension DeckController {
    /// The theme's colours as the style definitions name them (`accent1`, `lt1`...).
    func tableStyleColors(_ deckTheme: DeckTheme? = nil) -> ColorContext {
        let theme = deckTheme ?? self.theme
        var t = PptxTheme(nil)
        t.colors["dk1"] = theme.text
        t.colors["lt1"] = theme.background
        t.colors["dk2"] = Color(0xFF1F2A44)
        t.colors["lt2"] = Color(0xFFE8EBF0)
        for (i, a) in theme.accents.prefix(6).enumerated() { t.colors["accent\(i + 1)"] = a }
        return ColorContext(theme: t)
    }

    /// A built-in style's definition by id; nil for "No Style" and ids the app does not know.
    static func builtinTableStyle(_ id: String?) -> XNode? {
        guard let id, let xml = PptxTemplates.builtinTableStyles[id] else { return nil }
        return XNode.parse(Data(xml.utf8))
    }

    /// Whether the style is drawn by `dressTable` (the Medium Style 2 colours and the plain grid keep their own path).
    static func drawsFromDefinition(_ id: String?) -> Bool {
        guard let id, !id.isEmpty, id != TableLook.plain.styleId, !mediumStyle2Ids.contains(id) else { return false }
        return builtinTableStyle(id) != nil
    }

    /// The text look a style gives the cell at (row, column) of a table `rows` by `cols`, as the reader works it out:
    /// the whole table's colour, then the row and column bands, then the first/last column, last row and header.
    func tableTextLook(_ style: XNode?, _ o: TableOptions, row r: Int, column c: Int, rows: Int, cols: Int,
                       colors: ColorContext) -> (bold: Bool, color: Color?) {
        guard let style else { return (false, nil) }
        func part(_ n: String) -> SlideContext.TablePartStyle? { SlideContext.tablePart(style, n, colors: colors) }
        var look: (bold: Bool, color: Color?) = (false, part("a:wholeTbl")?.textColor)
        var parts: [SlideContext.TablePartStyle] = []
        let k = r - (o.headerRow ? 1 : 0)
        if o.bandedRows, k >= 0, let p = part(k % 2 == 0 ? "a:band1H" : "a:band2H") { parts.append(p) }
        let kc = c - (o.firstColumn ? 1 : 0)
        if o.bandedColumns, kc >= 0, let p = part(kc % 2 == 0 ? "a:band1V" : "a:band2V") { parts.append(p) }
        if o.firstColumn, c == 0, let p = part("a:firstCol") { parts.append(p) }
        if o.lastColumn, c == cols - 1, let p = part("a:lastCol") { parts.append(p) }
        if o.totalRow, r == rows - 1, r > 0, let p = part("a:lastRow") { parts.append(p) }
        if o.headerRow, r == 0, let p = part("a:firstRow") { parts.append(p) }
        for p in parts {
            if let b = p.bold { look.bold = b }
            if let col = p.textColor { look.color = col }
        }
        return look
    }

    /// Dress the table `s` in the built-in style `styleId` with options `o`: the cell fills, the table's rules and the cells'
    /// text weight and colour come from the style's definition (read the way a saved file would be), the user's own shading
    /// and text colours stay. `doc` is the table's text document, changed in place.
    func dressTable(_ doc: inout RichDocument, shape s: SlideShape, tableId id: String, styleId: String, options o: TableOptions) {
        let colors = tableStyleColors()
        let oldStyle = doc.tableStyles[id]
        let oldOptions = TableOptions(headerRow: oldStyle?.headerRow ?? true, bandedRows: oldStyle?.bandRows ?? (oldStyle?.bandFill != nil),
                                      firstColumn: oldStyle?.firstColumn ?? false, lastColumn: oldStyle?.lastColumn ?? false,
                                      totalRow: oldStyle?.totalRow ?? false, bandedColumns: oldStyle?.bandedColumns ?? false)
        let oldDefinition = DeckController.builtinTableStyle(oldStyle?.styleId)
        let definition = DeckController.builtinTableStyle(styleId)
        let cells = doc.paragraphs.compactMap { $0.cell }.filter { $0.table == id }
        let rows = (cells.map { $0.row + $0.rowSpan }.max() ?? 1), cols = (cells.map { $0.column + $0.span }.max() ?? 1)

        // 1. The fills and rules: a one-table copy of the deck, named for the style, written and read back.
        var probe = doc
        for i in probe.paragraphs.indices {
            guard var c = probe.paragraphs[i].cell, c.table == id else { continue }
            c.fill = nil; c.styleFilled = nil; c.borders = CellRef.CellBorders()
            probe.paragraphs[i].cell = c
        }
        var ts = doc.tableStyles[id] ?? TableStyle()
        var pts = ts
        pts.styleId = styleId; pts.headerRow = o.headerRow
        pts.bandFill = o.bandedRows ? Color(0xFF808080) : nil; pts.bandAltFill = nil
        pts.totalRow = o.totalRow; pts.firstColumn = o.firstColumn; pts.lastColumn = o.lastColumn; pts.bandedColumns = o.bandedColumns
        probe.tableStyles[id] = pts
        var shape = _state(s)
        shape.text = probe
        let slide = SlideState(id: 1, layout: .blank, hidden: false, notes: slides[0].notes.document, shapes: [shape])
        let state = DeckState(slides: [slide], current: 0, slideSize: slideSize, theme: theme, ownTemplates: true, recolourTheme: false)
        var drawn: RichDocument? = nil
        if let data = try? PptxWriter.write(state, theme: theme, package: nil, ownTemplates: true),
           let (read, _, _) = try? Pptx.read(data) {
            drawn = read.slides.first?.shapes.first(where: { $0.kind == .table })?.text
        }
        var fills: [Int: [Int: CellRef]] = [:]
        for c in drawn?.paragraphs.compactMap({ $0.cell }) ?? [] { fills[c.row, default: [:]][c.column] = c }
        if let drawn, let rts = drawn.tableStyles.values.first {
            ts.headerFill = rts.headerFill; ts.bandFill = rts.bandFill; ts.bandAltFill = rts.bandAltFill
            ts.borders = rts.borders; ts.borderColor = rts.borderColor; ts.edges = rts.edges; ts.borderWidth = rts.borderWidth
        }
        ts.styleId = styleId; ts.headerRow = o.headerRow
        ts.totalRow = o.totalRow; ts.firstColumn = o.firstColumn; ts.lastColumn = o.lastColumn; ts.bandedColumns = o.bandedColumns
        if !o.bandedRows { ts.bandFill = nil; ts.bandAltFill = nil }
        ts.bandRows = o.bandedRows

        // 2. The cells: the style's fill where the cell has none of its own; text weight and colour moved from the old
        // style's to the new one's where the run still shows the old one's (a colour the user chose stays).
        for i in doc.paragraphs.indices {
            guard var c = doc.paragraphs[i].cell, c.table == id else { continue }
            // A style with no definition here (Table Grid, Medium Style 2) has its text look baked on the runs: a white bold
            // header, bold first/last column and total row. Count that as the old look so it moves with the style.
            let was: (bold: Bool, color: Color?) = (oldDefinition == nil || oldStyle?.styleId == TableLook.plain.styleId) ? {
                if oldStyle?.styleId == TableLook.plain.styleId { return (false, nil) }  // Table Grid: plain text, nothing baked
                let head = oldOptions.headerRow && c.row == 0
                let bold = head || (oldOptions.firstColumn && c.column == 0) || (oldOptions.lastColumn && c.column == cols - 1)
                    || (oldOptions.totalRow && c.row == rows - 1 && c.row > 0)
                return (bold, head ? Color(0xFFFFFFFF) : nil)
            }() : tableTextLook(oldDefinition, oldOptions, row: c.row, column: c.column, rows: rows, cols: cols, colors: colors)
            let now = tableTextLook(definition, o, row: c.row, column: c.column, rows: rows, cols: cols, colors: colors)
            var runs = doc.paragraphs[i].runs.isEmpty ? [Run(length: doc.paragraphs[i].text.count)] : doc.paragraphs[i].runs
            for j in runs.indices {
                if runs[j].style.bold == was.bold { runs[j].style.bold = now.bold }
                if runs[j].style.color == was.color { runs[j].style.color = now.color }
            }
            doc.paragraphs[i].runs = runs
            if c.fill == nil || c.styleFilled == true {
                let f = fills[c.row]?[c.column]?.fill
                c.fill = f; c.styleFilled = f == nil ? nil : true
            }
            doc.paragraphs[i].cell = c
        }
        doc.tableStyles[id] = ts
    }
}
