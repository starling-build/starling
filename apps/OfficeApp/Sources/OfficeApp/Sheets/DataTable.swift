import Foundation

/// Data → What-If Analysis → Data Table. `{=TABLE(row input, column input)}`.
/// The selection holds the formulas and the input values around the result
/// block; the block's cells are filled by putting each input value into the
/// input cell and reading the formula back. The file keeps it as one
/// `<f t="dataTable" ref= dt2D= dtr= r1= r2=/>` on the block's first cell
/// and plain values in the rest, which is how it is read and written back.
enum DataTableProblem: Equatable {
    case selectionTooSmall
    case needsInput
    case inputInsideTable
    case sameInput
    case inputHasNoPlace
}

extension WorkbookController {
    /// `selection` is the whole block: formulas row and/or input column included.
    /// `rowInput` takes the values across the top row, `colInput` the ones down the left column.
    @discardableResult
    func dataTable(selection sel: CellRange, rowInput: CellAddress?, colInput: CellAddress?) -> DataTableProblem? {
        guard rowInput != nil || colInput != nil else { return .needsInput }
        let two = rowInput != nil && colInput != nil
        if sel.bottom - sel.top < 1 || sel.right - sel.left < 1 { return .selectionTooSmall }
        if let r = rowInput, let c = colInput, r == c { return .sameInput }
        let block = CellRange(top: sel.top + 1, left: sel.left + 1, bottom: sel.bottom, right: sel.right)
        for i in [rowInput, colInput].compactMap({ $0 }) where block.contains(i) { return .inputInsideTable }
        let all = (block.top...block.bottom).flatMap { r in (block.left...block.right).map { CellAddress(row: r, col: $0) } }
        if refusesEdit(all) { return nil }
        let ws = sheet
        var out: [CellAddress: CellValue] = [:]
        // Each input cell is restored before this returns; nothing of the trial runs reaches the undo history.
        let origRow = rowInput.map { ws.cells[$0] }, origCol = colInput.map { ws.cells[$0] }
        func put(_ a: CellAddress, _ v: CellValue) {
            var c = ws.cells[a] ?? Cell(input: "")
            c.formula = nil; c.rawFormula = nil; c.arrayRef = nil
            switch v {
            case .number(let n): c.input = String(n)
            case .text(let t): c.input = t
            case .bool(let b): c.input = b ? "TRUE" : "FALSE"
            default: c.input = ""
            }
            c.value = v
            ws.cells[a] = c
        }
        func restore() {
            if let r = rowInput, let o = origRow { ws.cells[r] = o }
            if let c = colInput, let o = origCol { ws.cells[c] = o }
            engine.recalculate()
        }
        for r in block.top...block.bottom {
            for c in block.left...block.right {
                let a = CellAddress(row: r, col: c)
                if two {
                    put(rowInput!, ws.value(CellAddress(row: sel.top, col: c)))
                    put(colInput!, ws.value(CellAddress(row: r, col: sel.left)))
                    engine.recalculate()
                    out[a] = ws.value(CellAddress(row: sel.top, col: sel.left))
                } else if let ri = rowInput {
                    put(ri, ws.value(CellAddress(row: sel.top, col: c)))
                    engine.recalculate()
                    out[a] = ws.value(CellAddress(row: r, col: sel.left))
                } else if let ci = colInput {
                    put(ci, ws.value(CellAddress(row: r, col: sel.left)))
                    engine.recalculate()
                    out[a] = ws.value(CellAddress(row: sel.top, col: c))
                }
            }
        }
        restore()
        var attrs = ""
        if two { attrs += " dt2D=\"1\"" }
        if rowInput != nil { attrs += " dtr=\"1\"" }
        let first = CellAddress(row: block.top, col: block.left)
        let r1 = (rowInput ?? colInput)!.a1
        let raw = "<f t=\"dataTable\" ref=\"\(CellRange(top: block.top, left: block.left, bottom: block.bottom, right: block.right).a1)\"\(attrs) r1=\"\(r1)\"" + (two ? " r2=\"\(colInput!.a1)\"" : "") + "/>"
        structural {
            for (a, v) in out {
                var c = ws.cells[a] ?? Cell(input: "")
                c.formula = nil; c.arrayRef = nil; c.rawFormula = a == first ? raw : nil
                c.input = NumberFormat.display(v, "General", width: 255).text
                c.value = v; c.cached = v
                ws.cells[a] = c
            }
        }
        return nil
    }
}
