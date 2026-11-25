import Foundation
import OfficeText
import FlutterSwiftBridge

// S-TB-1e: table borders and the pen. A cell's four edge lines are `CellRef.borders`; an edge shared by two cells is set on
// both (as PowerPoint writes it), so neither neighbour paints over the other.
extension DeckController {
    /// A side (or the lines between cells) of the cells the user picked.
    enum TableBorderSide: CaseIterable { case top, bottom, left, right, insideH, insideV }

    /// The pen: the line the Borders menu and the drawing tool lay down.
    struct TablePen: Equatable {
        var width: Double = 1
        var color: Color = Color(0xFF000000)
        /// PowerPoint's preset dash name; "solid" is a plain line.
        var dash: String = "solid"
        var line: CellRef.CellLine { CellRef.CellLine(width: width, color: color, dash: SlidePainter.dashPattern(dash == "solid" ? nil : dash)) }
    }

    /// The pen's weights and dashes as PowerPoint offers them.
    static let penWeights: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2.25, 3, 4.5, 6]
    static let penDashes: [(name: String, label: String)] = [
        ("solid", "Solid"), ("sysDot", "Round Dot"), ("sysDash", "Square Dot"), ("dash", "Dash"),
        ("dashDot", "Dash Dot"), ("lgDash", "Long Dash"), ("lgDashDot", "Long Dash Dot"), ("lgDashDotDot", "Long Dash Dot Dot")]

    /// The preset dash name a pattern came from (nil is solid), for the writer.
    static func penDashName(_ pattern: [Double]?) -> String? {
        guard let pattern else { return nil }
        return penDashes.first { SlidePainter.dashPattern($0.name) == pattern }?.name
    }

    /// Lay `line` (nil: no line at all) on the given sides of `block` (nil: the whole table), one undo step. Neighbouring
    /// cells get the matching opposite edge.
    func setTableBorders(_ sides: Set<TableBorderSide>, line: CellRef.CellLine?, block: CellBlock? = nil) {
        guard let s = selection.first, s.kind == .table, let id = s.tableId, let text = s.text, !sides.isEmpty else { return }
        var doc = text.document
        let cells = doc.paragraphs.compactMap { $0.cell }.filter { $0.table == id }
        guard !cells.isEmpty else { return }
        let b = block ?? CellBlock(table: id, rows: 0 ... (cells.map { $0.row + $0.rowSpan - 1 }.max() ?? 0),
                                   columns: 0 ... (cells.map { $0.column + $0.span - 1 }.max() ?? 0))
        let value = line ?? CellRef.CellLine.hidden
        enum Edge { case l, r, t, b }
        var todo: [(row: Int, col: Int, edge: Edge)] = []
        let r0 = b.rows.lowerBound, r1 = b.rows.upperBound, c0 = b.columns.lowerBound, c1 = b.columns.upperBound
        for c in c0 ... c1 {
            if sides.contains(.top) { todo.append((r0, c, .t)); todo.append((r0 - 1, c, .b)) }
            if sides.contains(.bottom) { todo.append((r1, c, .b)); todo.append((r1 + 1, c, .t)) }
            if sides.contains(.insideH), r0 < r1 { for r in r0 ..< r1 { todo.append((r, c, .b)); todo.append((r + 1, c, .t)) } }
        }
        for r in r0 ... r1 {
            if sides.contains(.left) { todo.append((r, c0, .l)); todo.append((r, c0 - 1, .r)) }
            if sides.contains(.right) { todo.append((r, c1, .r)); todo.append((r, c1 + 1, .l)) }
            if sides.contains(.insideV), c0 < c1 { for c in c0 ..< c1 { todo.append((r, c, .r)); todo.append((r, c + 1, .l)) } }
        }
        var changed = false
        for t in todo where t.row >= 0 && t.col >= 0 {
            for i in doc.paragraphs.indices {
                guard var c = doc.paragraphs[i].cell, c.table == id, c.covers(row: t.row, column: t.col) else { continue }
                // Only the edge that really lies on the cell's own side: a merged cell's inner positions are not its edges.
                switch t.edge {
                case .t: guard c.row == t.row else { continue }; if c.borders.top != value { c.borders.top = value; changed = true }
                case .b: guard c.row + c.rowSpan - 1 == t.row else { continue }; if c.borders.bottom != value { c.borders.bottom = value; changed = true }
                case .l: guard c.column == t.col else { continue }; if c.borders.left != value { c.borders.left = value; changed = true }
                case .r: guard c.column + c.span - 1 == t.col else { continue }; if c.borders.right != value { c.borders.right = value; changed = true }
                }
                doc.paragraphs[i].cell = c
            }
        }
        guard changed else { return }
        if !_penStrokeOpen || !_penStrokeSaved { _checkpoint() }
        if _penStrokeOpen { _penStrokeSaved = true }
        text.load(doc)
        _changed()
    }

    /// The pen or eraser touching one cell's edge: lays the pen's line (draw) or hides the line (eraser) on that edge.
    func penTouch(_ shape: SlideShape, row: Int, column: Int, side: CellSide) {
        guard tableTool != .none, shape.kind == .table, let id = shape.tableId, let text = shape.text else { return }
        if selection.first !== shape || selection.count != 1 { selectShapes([shape]) }
        guard let cell = text.document.paragraphs.compactMap({ $0.cell }).first(where: { $0.table == id && $0.row == row && $0.column == column })
        else { return }
        let block = CellBlock(table: id, rows: row ... row + cell.rowSpan - 1, columns: column ... column + cell.span - 1)
        let which: TableBorderSide
        switch side {
        case .top: which = .top
        case .bottom: which = .bottom
        case .left: which = .left
        default: which = .right
        }
        setTableBorders([which], line: tableTool == .draw ? tablePen.line : nil, block: block)
    }

    /// The pen stroke starts (true) or ends (false): everything drawn between is one undo step.
    func penStroke(_ on: Bool) {
        _penStrokeOpen = on
        _penStrokeSaved = false
    }

    /// "Reset to table style": drops the user's own shading and border lines from the cells (the selected ones, else the
    /// whole table), so the look comes from the table's style again. One undo step. Does nothing for a table that
    /// has no style (its look is its own cells); a style defined in the file works like a built-in one.
    func resetTableToStyle(block: CellBlock? = nil) {
        guard let s = selection.first, s.kind == .table, let id = s.tableId, let text = s.text else { return }
        var doc = text.document
        guard let ts = doc.tableStyles[id], let styleId = ts.styleId else { return }
        // Own shading is a fill the style did not give; borders are always the user's.
        func isOwn(_ c: CellRef) -> Bool { (c.fill != nil && c.styleFilled != true) || !c.borders.isEmpty }
        let touched = doc.paragraphs.contains { p in
            guard let c = p.cell, c.table == id, isOwn(c) else { return false }
            return block.map { $0.contains(c) } ?? true
        }
        guard touched else { return }
        // What the style alone paints: a one-table copy of the deck, written and read back (the file's own
        // tableStyles.xml travels with it, so a style defined there works as well as a built-in one).
        var probe = doc
        for i in probe.paragraphs.indices {
            guard var c = probe.paragraphs[i].cell, c.table == id else { continue }
            c.fill = nil; c.styleFilled = nil; c.borders = CellRef.CellBorders()
            probe.paragraphs[i].cell = c
        }
        var shape = _state(s)
        shape.text = probe
        let slide = SlideState(id: 1, layout: .blank, hidden: false, notes: slides[0].notes.document, shapes: [shape])
        let state = DeckState(slides: [slide], current: 0, slideSize: slideSize, theme: theme, ownTemplates: true, recolourTheme: false)
        var fills: [Int: [Int: Color]] = [:]
        if let data = try? PptxWriter.write(state, theme: theme, package: package, ownTemplates: true),
           let (read, _, _) = try? Pptx.read(data),
           let drawn = read.slides.first?.shapes.first(where: { $0.kind == .table })?.text {
            for c in drawn.paragraphs.compactMap({ $0.cell }) { if let f = c.fill { fills[c.row, default: [:]][c.column] = f } }
        }
        _ = styleId
        for i in doc.paragraphs.indices {
            guard var c = doc.paragraphs[i].cell, c.table == id, block.map({ $0.contains(c) }) ?? true, isOwn(c) else { continue }
            let f = fills[c.row]?[c.column]
            c.fill = f; c.styleFilled = f == nil ? nil : true
            c.borders = CellRef.CellBorders()
            doc.paragraphs[i].cell = c
        }
        _checkpoint(); text.load(doc); _changed()
    }
}
