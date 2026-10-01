// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Every change to a workbook goes through here: typing into cells,
// clearing, formatting, sheets added and renamed. Each is one undo step
// (a list of the cells it changed, before and after), and each ends in a
// recalculation and a notification. The selection lives here too, so the
// grid, the formula bar, the name box and the status bar agree.

import Flutter
import Foundation

final class WorkbookController: ChangeNotifier {
    private(set) var book: Workbook
    private(set) var engine: CalcEngine
    /// Bumped on every change; painters compare it to decide to repaint.
    private(set) var revision = 0
    /// Edits since open or save, for the title's dirty mark.
    private(set) var edits = 0

    var activeSheet = 0 {
        didSet { if activeSheet != oldValue { _notify(selectionOnly: true) } }
    }
    /// The cell that typing goes into, and the selected range around it.
    private(set) var active = CellAddress(row: 0, col: 0)
    private(set) var selection = CellRange(CellAddress(row: 0, col: 0))
    /// Where a shift-extension started.
    private(set) var anchor = CellAddress(row: 0, col: 0)

    var sheet: Worksheet { book.sheets[activeSheet] }

    override init() {
        book = Workbook()
        engine = CalcEngine(book)
        super.init()
    }

    /// Replace the workbook (open a file, new workbook).
    func load(_ b: Workbook) {
        book = b
        engine = CalcEngine(b)
        _parseAll()
        engine.recalculate()
        activeSheet = 0
        active = CellAddress(row: 0, col: 0)
        selection = CellRange(active)
        anchor = active
        _undo.removeAll(); _redo.removeAll()
        edits = 0
        _notify()
    }

    func markSaved() { edits = 0; _notify(selectionOnly: true) }

    // MARK: Selection

    func select(_ a: CellAddress, extend: Bool = false) {
        let a = _clamp(a)
        if extend {
            selection = CellRange(anchor, a)
            _extentEnd = a
        } else {
            active = a
            anchor = a
            selection = CellRange(a)
            _extentEnd = a
        }
        _notify(selectionOnly: true)
    }

    /// Select a whole range with `active` inside it (a click on a header,
    /// a name box entry).
    func select(range: CellRange, active a: CellAddress? = nil) {
        selection = range
        active = a ?? range.topLeft
        anchor = active
        _extentEnd = range.bottomRight
        _notify(selectionOnly: true)
    }

    /// The far corner of a shift-selection, which arrow keys move.
    private(set) var _extentEnd = CellAddress(row: 0, col: 0)

    /// Move within a selection with Enter/Tab (Excel keeps a multi-cell
    /// selection and walks the active cell through it).
    func advance(rows dr: Int, cols dc: Int) {
        if selection.isSingle {
            select(CellAddress(row: active.row + dr, col: active.col + dc))
            return
        }
        var r = active.row, c = active.col
        if dc != 0 {
            c += dc
            if c > selection.right { c = selection.left; r += 1 }
            if c < selection.left { c = selection.right; r -= 1 }
            if r > selection.bottom { r = selection.top }
            if r < selection.top { r = selection.bottom }
        } else {
            r += dr
            if r > selection.bottom { r = selection.top; c += 1 }
            if r < selection.top { r = selection.bottom; c -= 1 }
            if c > selection.right { c = selection.left }
            if c < selection.left { c = selection.right }
        }
        active = CellAddress(row: r, col: c)
        _notify(selectionOnly: true)
    }

    /// Ctrl+arrow: to the edge of the current block of data, or to the
    /// next block, or to the sheet's edge — Excel's End-arrow.
    func edge(from a: CellAddress, rows dr: Int, cols dc: Int) -> CellAddress {
        func filled(_ x: CellAddress) -> Bool { !(sheet.cells[x]?.value.isEmpty ?? true) || (sheet.cells[x]?.isFormula ?? false) }
        func inside(_ x: CellAddress) -> Bool { x.row >= 0 && x.col >= 0 && x.row < CellAddress.maxRows && x.col < CellAddress.maxCols }
        var p = a
        let step = { (x: CellAddress) in CellAddress(row: x.row + dr, col: x.col + dc) }
        let next = step(p)
        guard inside(next) else { return p }
        let used = sheet.usedExtent
        let limitR = dr > 0 ? max(used.row + 1, a.row) : 0
        let limitC = dc > 0 ? max(used.col + 1, a.col) : 0
        if filled(p) && filled(next) {
            while inside(step(p)) && filled(step(p)) { p = step(p) }
            return p
        }
        p = next
        while inside(step(p)) && !filled(p) {
            if (dr > 0 && p.row >= limitR) || (dc > 0 && p.col >= limitC) {
                return dr > 0 ? CellAddress(row: CellAddress.maxRows - 1, col: p.col)
                    : dc > 0 ? CellAddress(row: p.row, col: CellAddress.maxCols - 1) : p
            }
            p = step(p)
        }
        return p
    }

    private func _clamp(_ a: CellAddress) -> CellAddress {
        CellAddress(row: max(0, min(a.row, CellAddress.maxRows - 1)), col: max(0, min(a.col, CellAddress.maxCols - 1)))
    }

    // MARK: Editing

    /// What a cell's editor and the formula bar show.
    func input(_ a: CellAddress) -> String {
        guard let c = sheet.cells[a] else { return "" }
        if let f = c.formula { return Formula.text(f) }
        if case .number(let n) = c.value {
            let fmt = book.style(c.style).numberFormat
            // A date shows as a date in the bar, a percent as a percent.
            if fmt.contains("%") { return NumberFormat.full(n * 100) + "%" }
            if NumberFormat.format(n, fmt).text != NumberFormat.general(n), fmt.lowercased().contains("y") || fmt.lowercased().contains("d") {
                return NumberFormat.format(n, fmt.contains("h") ? "m/d/yyyy h:mm" : "m/d/yyyy").text
            }
            return NumberFormat.full(n)
        }
        return c.input
    }

    /// Type `text` into `a` (Enter in the cell or the formula bar).
    func setInput(_ text: String, at a: CellAddress) {
        setInputs([(a, text)])
    }

    /// Several cells in one step (paste, fill, Ctrl+Enter).
    func setInputs(_ items: [(CellAddress, String)], sheet si: Int? = nil) {
        let si = si ?? activeSheet
        let ws = book.sheets[si]
        var before: [CellAddress: Cell?] = [:]
        for (a, text) in items {
            if before[a] == nil { before[a] = .some(ws.cells[a]) }
            var cell = ws.cells[a] ?? Cell(input: "")
            if text.isEmpty {
                if cell.style == 0 { ws.cells[a] = nil; continue }
                cell.input = ""; cell.formula = nil; cell.value = .empty
                ws.cells[a] = cell
                continue
            }
            cell.input = text
            if let parsed = InputParser.parse(text) {
                cell.formula = nil
                cell.value = parsed.value
                // A typed format sticks only on a cell still in General.
                if let fmt = parsed.format, book.style(cell.style).numberFormat == "General" {
                    var st = book.style(cell.style)
                    st.numberFormat = fmt
                    cell.style = book.styleIndex(st)
                }
            } else {
                do {
                    cell.formula = try Formula.parse(text)
                    cell.value = .empty
                } catch {
                    // Excel refuses the entry; we keep it as text so nothing typed is lost.
                    cell.formula = nil
                    cell.value = .text(text)
                }
            }
            ws.cells[a] = cell
        }
        _record(sheet: si, before: before)
    }

    /// Delete: clear the selection's contents, keeping formats.
    func clearContents(_ r: CellRange? = nil) {
        let r = r ?? selection
        let items = sheet.cells.keys.filter { r.contains($0) }.map { ($0, "") }
        guard !items.isEmpty else { return }
        setInputs(items)
    }

    /// Apply a change to the style of every cell in the selection.
    func setStyle(_ change: (inout CellStyle) -> Void, range: CellRange? = nil) {
        let r = range ?? selection
        let ws = sheet
        var before: [CellAddress: Cell?] = [:]
        // Formatting a huge range (a whole column) touches only cells that exist
        // plus the visible block the user selected; Excel stores column styles,
        // which arrive with .xlsx in X2.
        let area = r.rows * r.cols
        let targets: [CellAddress] = area <= 20_000
            ? (r.top ... r.bottom).flatMap { row in (r.left ... r.right).map { CellAddress(row: row, col: $0) } }
            : ws.cells.keys.filter { r.contains($0) }
        for a in targets {
            before[a] = .some(ws.cells[a])
            var cell = ws.cells[a] ?? Cell(input: "")
            var st = book.style(cell.style)
            change(&st)
            cell.style = book.styleIndex(st)
            ws.cells[a] = cell
        }
        _record(sheet: activeSheet, before: before, recalc: false)
    }

    func style(at a: CellAddress) -> CellStyle { book.style(sheet.cells[a]?.style ?? 0) }

    func setColumnWidth(_ col: Int, _ w: Double) {
        sheet.colWidths[col] = max(0, w)
        _bump()
    }

    func setRowHeight(_ row: Int, _ h: Double) {
        sheet.rowHeights[row] = max(0, h)
        _bump()
    }

    // MARK: Sheets

    func addSheet() {
        book.sheets.insert(Worksheet(name: book.nextSheetName()), at: activeSheet + 1)
        activeSheet += 1
        _bump()
    }

    @discardableResult
    func renameSheet(_ i: Int, _ name: String) -> Bool {
        let n = name.trimmingWhitespace()
        guard !n.isEmpty, n.count <= 31, !n.contains(where: { "[]:*?/\\".contains($0) }) else { return false }
        if let j = book.sheet(named: n), j != i { return false }
        let old = book.sheets[i].name
        book.sheets[i].name = n
        // Formulas that named the sheet follow it.
        for ws in book.sheets {
            for (a, c) in ws.cells {
                guard let f = c.formula else { continue }
                let g = Formula.mapRefs(f) { r in
                    var r = r
                    if r.sheet?.lowercased() == old.lowercased() { r.sheet = n }
                    return r
                }
                if g != f { ws.cells[a]?.formula = g; ws.cells[a]?.input = Formula.text(g) }
            }
        }
        _bump()
        return true
    }

    func deleteSheet(_ i: Int) {
        guard book.sheets.count > 1 else { return }
        book.sheets.remove(at: i)
        activeSheet = min(activeSheet, book.sheets.count - 1)
        engine.recalculate()
        _bump()
    }

    // MARK: Undo

    private struct Step {
        let sheet: Int
        let before: [CellAddress: Cell?]
        let after: [CellAddress: Cell?]
        let selection: CellRange
        let active: CellAddress
    }
    private var _undo: [Step] = []
    private var _redo: [Step] = []

    var canUndo: Bool { !_undo.isEmpty }
    var canRedo: Bool { !_redo.isEmpty }

    private func _record(sheet si: Int, before: [CellAddress: Cell?], recalc: Bool = true) {
        let ws = book.sheets[si]
        var after: [CellAddress: Cell?] = [:]
        for a in before.keys { after[a] = .some(ws.cells[a]) }
        _undo.append(Step(sheet: si, before: before, after: after, selection: selection, active: active))
        if _undo.count > 500 { _undo.removeFirst(_undo.count - 500) }
        _redo.removeAll()
        edits += 1
        if recalc { engine.recalculate() }
        _notify()
    }

    func undo() {
        guard let s = _undo.popLast() else { return }
        _apply(s.sheet, s.before)
        _redo.append(s)
        edits -= 1
        activeSheet = s.sheet
        selection = s.selection
        active = s.active
        anchor = active
        engine.recalculate()
        _notify()
    }

    func redo() {
        guard let s = _redo.popLast() else { return }
        _apply(s.sheet, s.after)
        _undo.append(s)
        edits += 1
        activeSheet = s.sheet
        engine.recalculate()
        _notify()
    }

    private func _apply(_ si: Int, _ cells: [CellAddress: Cell?]) {
        let ws = book.sheets[si]
        for (a, c) in cells { ws.cells[a] = c ?? nil }
    }

    // MARK: Plumbing

    private func _parseAll() {
        for ws in book.sheets {
            for (a, c) in ws.cells where c.formula == nil && c.input.hasPrefix("=") && c.input.count > 1 {
                ws.cells[a]?.formula = try? Formula.parse(c.input)
            }
        }
    }

    private func _bump() {
        edits += 1
        _notify()
    }

    private func _notify(selectionOnly: Bool = false) {
        revision += 1
        notifyListeners()
    }

    /// The status bar's figures for the selection: Sum, Average, Count.
    var selectionStats: (sum: Double, average: Double?, count: Int, numbers: Int) {
        var sum = 0.0, count = 0, numbers = 0
        let r = selection
        let keys: [CellAddress] = r.rows * r.cols <= sheet.cells.count
            ? (r.top ... r.bottom).flatMap { row in (r.left ... r.right).map { CellAddress(row: row, col: $0) } }
            : sheet.cells.keys.filter { r.contains($0) }
        for a in keys {
            let v = sheet.value(a)
            if v.isEmpty { continue }
            count += 1
            if let n = v.number { sum += n; numbers += 1 }
        }
        return (sum, numbers > 0 ? sum / Double(numbers) : nil, count, numbers)
    }
}
