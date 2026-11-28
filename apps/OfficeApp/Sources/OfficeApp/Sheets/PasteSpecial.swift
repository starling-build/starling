import Flutter
// Paste Special for Sheets: what to take from the copied cells (all, values,
// formulas, formats, column widths), an arithmetic operation against what is
// already there, skip blanks, and transpose. One undoable step.

import Foundation

struct PasteSpecial: Equatable, Sendable {
    enum What: String, CaseIterable, Sendable {
        case all, values, formulas, formats, columnWidths
        /// Excel's All except borders (Paste Options: No Borders).
        case allExceptBorders
        /// All, and the copied columns' widths (Keep Source Column Widths).
        case allWithColumnWidths
        /// Values and number formats (Values & Number Formatting).
        case valuesAndNumberFormats
        /// Values with the copied cells' whole format (Values & Source Formatting).
        case valuesAndFormats
        /// Comments and Notes: the copied cells' notes, nothing else.
        case comments
        /// Validation: the copied cells' data validation rules, nothing else.
        case validation
        /// Formulas and number formats.
        case formulasAndNumberFormats
        /// All using Source theme (a copy within the workbook has its theme already: as All).
        case allUsingSourceTheme
        /// All merging conditional formats: All, and the copied cells' conditional formats added to the
        /// pasted cells' own.
        case allMergingConditionalFormats

        /// Pastes the cells as All does.
        var isAll: Bool { [.all, .allUsingSourceTheme, .allMergingConditionalFormats].contains(self) }
    }
    enum Operation: String, CaseIterable, Sendable { case none, add, subtract, multiply, divide }
    var what: What = .all
    var operation: Operation = .none
    var skipBlanks = false
    var transpose = false
    /// Paste Link: each cell becomes a reference to the copied one.
    var link = false
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
            if how.what == .comments { _pasteNotes(clip, source: source, at: at, transpose: how.transpose, skipBlanks: how.skipBlanks); return }
            if how.what == .validation {
                if let source { _pasteValidation(clip, source: source, dst: dst, transpose: how.transpose) }
                return
            }
            if how.what == .columnWidths {
                // (Widths belong to columns: a turned block has none to give.)
                guard let source, !how.transpose else { return }
                for k in 0 ..< cols {
                    ws.colWidths[at.col + k] = source.colWidth(clip.range.left + k)
                    ws.widenedCols.remove(at.col + k)
                }
                return
            }
            if how.link {
                let prefix = clip.sheet == activeSheet || source == nil ? "" : Formula.quoteSheet(source!.name) + "!"
                for r in 0 ..< rows {
                    for c in 0 ..< cols {
                        let rel = how.transpose ? CellAddress(row: c, col: r) : CellAddress(row: r, col: c)
                        let from = CellAddress(row: clip.range.top + rel.row, col: clip.range.left + rel.col)
                        let to = CellAddress(row: dst.top + r, col: dst.left + c)
                        let text = "=" + prefix + from.a1
                        guard let f = try? Formula.parse(text) else { continue }
                        var cell = ws.cells[to] ?? Cell(input: "")
                        cell.rawFormula = nil; cell.keptAttrs = [:]; cell.cached = nil
                        cell.input = text; cell.formula = f; cell.value = .empty
                        ws.cells[to] = cell
                    }
                }
                return
            }
            if how.what == .allWithColumnWidths, let source, !how.transpose {
                for k in 0 ..< cols {
                    ws.colWidths[at.col + k] = source.colWidth(clip.range.left + k)
                    ws.widenedCols.remove(at.col + k)
                }
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
            if how.what == .allMergingConditionalFormats, let source {
                // A full paste: the notes and validation come too (Excel's lab, 2026-11-28), then the merged rules.
                _pasteNotes(clip, source: source, at: at, transpose: how.transpose, skipBlanks: how.skipBlanks)
                _pasteValidation(clip, source: source, dst: dst, transpose: how.transpose)
                _mergeConditionalFormats(clip, source: source, dst: dst, transpose: how.transpose)
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
        case .valuesAndNumberFormats:
            var c = constant(existing, src?.value ?? .empty)
            var st = book.style(existing?.style ?? 0)
            st.numberFormat = book.style(src?.style ?? 0).numberFormat
            c.style = book.styleIndex(st)
            result = c
        case .valuesAndFormats:
            guard let s = src else { return nil }
            var c = constant(s, s.value)
            c.style = s.style
            result = c
        case .formulas, .formulasAndNumberFormats:
            if var s = src {
                if !keepFormula, s.formula != nil || s.rawFormula != nil { s = constant(s, s.value) }
                s.style = existing?.style ?? 0
                if how.what == .formulasAndNumberFormats {
                    var st = book.style(s.style)
                    st.numberFormat = book.style(src?.style ?? 0).numberFormat
                    s.style = book.styleIndex(st)
                }
                result = s
            } else {
                var c = existing ?? Cell(input: "")
                c.formula = nil; c.rawFormula = nil; c.cached = nil; c.value = .empty; c.input = ""
                result = c
            }
        case .comments, .validation:
            return existing
        case .all, .columnWidths, .allWithColumnWidths, .allExceptBorders, .allUsingSourceTheme, .allMergingConditionalFormats:
            if var s = src {
                if !keepFormula, s.formula != nil || s.rawFormula != nil { let st = s.style; s = constant(s, s.value); s.style = st }
                if how.what == .allExceptBorders {
                    var st = book.style(s.style)
                    st.borders = CellStyle.Borders()
                    s.style = book.styleIndex(st)
                }
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
            if how.what.isAll || [.allWithColumnWidths, .allExceptBorders, .valuesAndFormats].contains(how.what) {
                out.style = r.style
            } else if how.what == .formulasAndNumberFormats {
                out.style = r.style
            } else { out.style = existing?.style ?? 0 }
            return out
        }
        return result
    }
}

// MARK: Notes, validation and conditional formats

extension WorkbookController {
    /// Where a copied range (in the source sheet) lands, turned or not; nil when it holds none of the clip.
    private func _landing(_ r: CellRange, clip: Clip, at: CellAddress, transpose: Bool) -> CellRange? {
        guard let x = r.intersection(clip.range) else { return nil }
        let t = x.top - clip.range.top, l = x.left - clip.range.left
        let out = transpose
            ? CellRange(top: at.row + l, left: at.col + t, bottom: at.row + l + x.cols - 1, right: at.col + t + x.rows - 1)
            : CellRange(top: at.row + t, left: at.col + l, bottom: at.row + t + x.rows - 1, right: at.col + l + x.cols - 1)
        guard out.bottom < CellAddress.maxRows, out.right < CellAddress.maxCols else { return nil }
        return out
    }

    /// A kept rule element (a `<dataValidation>` or a `<conditionalFormatting>`) as pasted: its ranges cut to
    /// the clip and moved to the paste, its formulas re-read from the rule's new first cell, so each pasted
    /// cell tests what its copied cell tested. Nil when it covers none of the clip.
    private func _pastedRule(_ text: String, clip: Clip, at: CellAddress, transpose: Bool) -> String? {
        guard let tagEnd = text.firstIndex(of: ">"),
              let a = text.findRange(of: " sqref=\"", in: text.startIndex ..< tagEnd),
              let b = text.findRange(of: "\"", in: a.upperBound ..< text.endIndex) else { return nil }
        let ranges = text[a.upperBound ..< b.lowerBound].split(separator: " ").compactMap { CellRange(String($0)) }
        guard let old = ranges.first?.topLeft,
              let new = ranges.lazy.compactMap({ self._landing($0, clip: clip, at: at, transpose: transpose) }).first?.topLeft
        else { return nil }
        let dr = new.row - old.row, dc = new.col - old.col
        return KeptRefs.element(text, range: { self._landing($0, clip: clip, at: at, transpose: transpose) }, ref: { r in
            if case .ref(let s) = Formula.shifted(.ref(r), rows: dr, cols: dc) { return s }
            return nil
        })
    }

    /// Paste Special > Comments and Notes: each copied note onto its pasted cell, in place of the note there.
    func _pasteNotes(_ clip: Clip, source: Worksheet?, at: CellAddress, transpose: Bool, skipBlanks: Bool) {
        guard let source else { return }
        let ws = sheet
        let copied = source.notes.filter { n in !n.threaded && n.at.map { clip.range.contains($0) } ?? false }
        guard !copied.isEmpty || !skipBlanks else { return }
        var landed: [SheetNote] = []
        for n in copied {
            guard let from = n.at, let to = _landing(CellRange(from), clip: clip, at: at, transpose: transpose)?.topLeft else { continue }
            landed.append(SheetNote(origin: nil, at: to, author: n.author, text: n.text, edited: true))
        }
        // Each pasted cell takes the copied cell's note; (skip blanks) a copied cell without one leaves the
        // pasted cell's note alone.
        let rows = transpose ? clip.range.cols : clip.range.rows, cols = transpose ? clip.range.rows : clip.range.cols
        let dst = CellRange(top: at.row, left: at.col, bottom: at.row + rows - 1, right: at.col + cols - 1)
        if skipBlanks {
            for n in landed { Self._dropNotes(ws, in: CellRange(n.at!)) }
        } else {
            Self._dropNotes(ws, in: dst)
        }
        ws.notes += landed
    }

    /// Paste Special > Validation: the pasted cells take the copied cells' rules and lose their own.
    func _pasteValidation(_ clip: Clip, source: Worksheet, dst: CellRange, transpose: Bool) {
        var pasted: [String] = []
        for (name, text) in source.keptElements where name == "dataValidations" {
            for kid in RawXML.split([UInt8](text.utf8)).children where kid.name == "dataValidation" {
                if let p = _pastedRule(kid.text, clip: clip, at: dst.topLeft, transpose: transpose) { pasted.append(p) }
            }
        }
        _takeCellsOutOfValidations([dst])
        for p in pasted { _appendValidation(p) }
    }

    /// All merging conditional formats: the copied cells' conditional formats join the pasted cells' own and
    /// come first, as Excel does (the pasted rules take priorities 1, 2, …; the sheet's own move down after them).
    func _mergeConditionalFormats(_ clip: Clip, source: Worksheet, dst: CellRange, transpose: Bool) {
        var pasted: [String] = []
        for (name, text) in source.keptElements where name == "conditionalFormatting" {
            if let p = _pastedRule(text, clip: clip, at: dst.topLeft, transpose: transpose) { pasted.append(p) }
        }
        guard !pasted.isEmpty else { return }
        var next = 1
        pasted = pasted.map { Self._renumberPriorities($0) { _ in defer { next += 1 }; return next } }
        let shift = next - 1
        let ws = sheet
        for k in ws.keptElements.indices where ws.keptElements[k].name == "conditionalFormatting" {
            ws.keptElements[k].text = Self._renumberPriorities(ws.keptElements[k].text) { $0 + shift }
        }
        let at = ws.keptElements.firstIndex { $0.name == "conditionalFormatting" } ?? ws.keptElements.count
        ws.keptElements.insert(contentsOf: pasted.map { (name: "conditionalFormatting", text: $0) }, at: at)
    }

    /// Each rule's ` priority="n"` in `text`, given the number `to` makes of it.
    static func _renumberPriorities(_ text: String, _ to: (Int) -> Int) -> String {
        var parts = text.components(separatedBy: " priority=\"")
        for k in parts.indices.dropFirst() {
            guard let q = parts[k].firstIndex(of: "\""), let old = Int(parts[k][..<q]) else { continue }
            parts[k] = "\(to(old))" + parts[k][q...]
        }
        return parts.joined(separator: " priority=\"")
    }
}

/// Paste Special's chord, with V: Ctrl+Alt (Windows, Linux) or Ctrl+Cmd (Excel for Mac), where the primary key is Cmd.
func isPasteSpecialChord(control: Bool, alt: Bool, meta: Bool, macKeys: Bool = KeyModifiers.primary == .meta) -> Bool {
    macKeys ? control && meta && !alt : control && alt && !meta
}

private extension Cell {
    var isBlank: Bool { formula == nil && rawFormula == nil && value.isEmpty && style == 0 && input.isEmpty }
}
