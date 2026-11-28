// Paste Special for Sheets: what to take from the copied cells (all, values,
// formulas, formats, column widths), an arithmetic operation against what is
// already there, skip blanks, and transpose. One undoable step.

import Foundation

struct PasteSpecial: Equatable, Sendable {
    enum What: String, CaseIterable, Sendable { case all, values, formulas, formats, columnWidths }
    enum Operation: String, CaseIterable, Sendable { case none, add, subtract, multiply, divide }
    var what: What = .all
    var operation: Operation = .none
    var skipBlanks = false
    var transpose = false
    /// Plain Paste.
    var isPlain: Bool { self == PasteSpecial() }
}

/// The last paste, kept so the Paste Options button can make it again another way (X-CL-1).
struct LastPaste {
    let clip: WorkbookController.Clip
    let how: PasteSpecial
    let at: CellAddress
    let sheet: Int
    /// What the paste filled.
    let range: CellRange
    let dataRevision: Int

    func with(dataRevision r: Int) -> LastPaste {
        LastPaste(clip: clip, how: how, at: at, sheet: sheet, range: range, dataRevision: r)
    }
}

extension WorkbookController {
    /// Excel's Paste Options button after a paste: the last paste, while nothing has changed the cells since
    /// and its sheet is the one shown.
    var pasteOptions: LastPaste? {
        guard let l = lastPaste, l.dataRevision == dataRevision, l.sheet == activeSheet else { return nil }
        return l
    }

    /// Make the last paste again by `how`, in its place of the one before: one undo step takes the new one back.
    func repaste(_ how: PasteSpecial) {
        guard let l = pasteOptions, how != l.how else { return }
        undo()
        select(range: CellRange(top: l.at.row, left: l.at.col, bottom: l.at.row, right: l.at.col), active: l.at)
        let was = dataRevision
        pasteSpecial(l.clip, how)
        // (Refused, say by a locked cell the turned block reaches: the first paste stands.)
        if dataRevision == was { redo(); lastPaste = l.with(dataRevision: dataRevision) }
    }

    /// Paste a copied clip at the selection by `how`. A clip that was cut is
    /// pasted as a copy (the source stays); "all" with nothing else set is the
    /// ordinary paste, which moves it.
    func pasteSpecial(_ clip: Clip, _ how: PasteSpecial) {
        let was = dataRevision
        defer {
            // A copy that went in: the Paste Options button can make it again another way. (A cut moved its
            // source, so there is nothing to make again.)
            if dataRevision != was, !clip.cut {
                lastPaste = LastPaste(clip: clip, how: how, at: selection.topLeft, sheet: activeSheet, range: selection,
                                      dataRevision: dataRevision)
            }
        }
        if how.isPlain { paste(clip); return }
        let at = selection.topLeft
        let rows = how.transpose ? clip.range.cols : clip.range.rows
        let cols = how.transpose ? clip.range.rows : clip.range.cols
        let dst = CellRange(top: at.row, left: at.col, bottom: at.row + rows - 1, right: at.col + cols - 1)
        guard dst.bottom < CellAddress.maxRows, dst.right < CellAddress.maxCols else { return }
        if refusesEdit(dst.cells) { return }
        let ws = sheet
        let source: Worksheet? = clip.sheet < book.sheets.count ? book.sheets[clip.sheet] : nil
        structural {
            if how.what == .columnWidths {
                // (Widths belong to columns: a turned block has none to give.)
                guard let source, !how.transpose else { return }
                for k in 0 ..< cols {
                    ws.colWidths[at.col + k] = source.colWidth(clip.range.left + k)
                    ws.widenedCols.remove(at.col + k)
                }
                return
            }
            for r in 0 ..< rows {
                for c in 0 ..< cols {
                    let rel = how.transpose ? CellAddress(row: c, col: r) : CellAddress(row: r, col: c)
                    let from = CellAddress(row: clip.range.top + rel.row, col: clip.range.left + rel.col)
                    let to = CellAddress(row: dst.top + r, col: dst.left + c)
                    let copied = _copied(clip.cells[rel], from: from, to: to)
                    if let out = _pasteOne(copied, existing: ws.cells[to], how: how, keepFormula: !how.transpose) {
                        ws.cells[to] = out.isBlank ? nil : out
                    } else if how.skipBlanks == false {
                        ws.cells[to] = nil
                    }
                }
            }
        }
        select(range: dst, active: at)
    }

    /// The cell that results at one place; nil clears it, `.some(existing)` keeps it.
    private func _pasteOne(_ src: Cell?, existing: Cell?, how: PasteSpecial, keepFormula: Bool) -> Cell? {
        let srcBlank = src == nil || (src!.formula == nil && src!.value.isEmpty && src!.rawFormula == nil)
        if how.skipBlanks && srcBlank { return existing ?? Cell(input: "") }
        func constant(_ base: Cell?, _ v: CellValue) -> Cell {
            var c = base ?? Cell(input: "")
            c.formula = nil; c.rawFormula = nil; c.cached = nil; c.keptAttrs = [:]
            c.value = v
            c.input = Cell.text(of: v)
            return c
        }
        var result: Cell?
        switch how.what {
        case .formats:
            var c = existing ?? Cell(input: "")
            c.style = src?.style ?? 0
            return c
        case .values:
            result = constant(existing, src?.value ?? .empty)
        case .formulas:
            if var s = src {
                if !keepFormula, s.formula != nil || s.rawFormula != nil { s = constant(s, s.value) }
                s.style = existing?.style ?? 0
                result = s
            } else {
                var c = existing ?? Cell(input: "")
                c.formula = nil; c.rawFormula = nil; c.cached = nil; c.value = .empty; c.input = ""
                result = c
            }
        case .all, .columnWidths:
            if var s = src {
                if !keepFormula, s.formula != nil || s.rawFormula != nil { let st = s.style; s = constant(s, s.value); s.style = st }
                result = s
            } else { result = nil }
        }
        // Arithmetic against what is there: numbers only; the result is a number.
        if how.operation != .none, let r = result, case .number(let b) = r.value, how.what != .formats {
            let a: Double
            switch existing?.value ?? .empty {
            case .number(let n): a = n
            case .empty: a = 0
            default: return existing   // text or error underneath is left as it is
            }
            let v: Double
            switch how.operation {
            case .add: v = a + b
            case .subtract: v = a - b
            case .multiply: v = a * b
            case .divide: if b == 0 { return constant(r, .error(.div0)) } else { v = a / b }
            case .none: v = b
            }
            var out = constant(existing ?? r, .number(v))
            if how.what == .all { out.style = r.style } else { out.style = existing?.style ?? 0 }
            return out
        }
        return result
    }
}

private extension Cell {
    var isBlank: Bool { formula == nil && rawFormula == nil && value.isEmpty && style == 0 && input.isEmpty }
}
