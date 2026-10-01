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
    /// Bumped by changes to cells, not by the selection moving: what
    /// caches of values (conditional-format statistics) key on.
    private(set) var dataRevision = 0
    /// Edits since open or save, for the title's dirty mark.
    private(set) var edits = 0

    var activeSheet = 0 {
        didSet {
            guard activeSheet != oldValue else { return }
            selectedDrawing = nil
            // Each sheet keeps its own selection, as Excel's do; a new one starts at A1.
            if oldValue < book.sheets.count {
                _selections[ObjectIdentifier(book.sheets[oldValue])] = (selection, active)
            }
            let saved = _selections[ObjectIdentifier(sheet)]
            selection = saved?.0 ?? CellRange(CellAddress(row: 0, col: 0))
            active = saved?.1 ?? CellAddress(row: 0, col: 0)
            anchor = active
            _extentEnd = selection.bottomRight
            _notify(selectionOnly: true)
        }
    }
    var _selections: [ObjectIdentifier: (CellRange, CellAddress)] = [:]
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
        _selections.removeAll()
        _parseAll()
        engine.recalculate()
        activeSheet = min(max(0, b.activeTab), b.sheets.count - 1)
        active = sheet.savedActive ?? CellAddress(row: 0, col: 0)
        selection = CellRange(active)
        anchor = active
        _extentEnd = active
        _undo.removeAll(); _redo.removeAll()
        edits = 0
        _notify()
    }

    func markSaved() { edits = 0; _notify(selectionOnly: true) }

    /// Before writing a file: each sheet's active cell and the front tab,
    /// so the file reopens where it was left.
    func stashViewState() {
        for (i, ws) in book.sheets.enumerated() {
            if i == activeSheet { ws.savedActive = active }
            else if let saved = _selections[ObjectIdentifier(ws)] { ws.savedActive = saved.1 }
        }
        book.activeTab = activeSheet
    }

    // MARK: Selection

    func select(_ a: CellAddress, extend: Bool = false) {
        _tabStart = nil
        selectedDrawing = nil
        let a = _clamp(a)
        if extend {
            selection = _withMerges(CellRange(anchor, a))
            _extentEnd = a
        } else {
            // A merged area selects as one cell, its top-left active.
            let m = sheet.merges.first { $0.contains(a) }
            active = m?.topLeft ?? a
            anchor = active
            selection = m ?? CellRange(a)
            _extentEnd = a
        }
        _notify(selectionOnly: true)
    }

    /// A range grown until no merged area straddles its edge.
    private func _withMerges(_ r: CellRange) -> CellRange {
        var r = r
        var grew = true
        while grew {
            grew = false
            for m in sheet.merges where m.intersects(r) {
                let u = r.union(m)
                if u != r { r = u; grew = true }
            }
        }
        return r
    }

    // MARK: Merge and freeze

    /// Merge & Center: the selection becomes one cell showing its
    /// top-left value, centred; selecting a merged area unmerges it.
    func toggleMerge() {
        let r = selection
        if let m = sheet.merges.first(where: { $0 == r }) {
            structural { sheet.merges.removeAll { $0 == m } }
            return
        }
        guard !r.isSingle, r.rows * r.cols <= 1_000_000 else { return }
        let others = sheet.cells.keys.filter { r.contains($0) && $0 != r.topLeft && !(sheet.cells[$0]?.value.isEmpty ?? true) }
        structural {
            // Excel keeps only the top-left value.
            for a in others { sheet.cells[a] = nil }
            sheet.merges.removeAll { $0.intersects(r) }
            sheet.merges.append(r)
            var c = sheet.cells[r.topLeft] ?? Cell(input: "")
            var st = book.style(c.style)
            st.hAlign = .center
            c.style = book.styleIndex(st)
            sheet.cells[r.topLeft] = c
        }
        if !others.isEmpty { onCommand?(.status("Merging keeps only the upper-left value")) }
    }

    /// Freeze the rows above and the columns left of `at` (A1 unfreezes).
    func freeze(at a: CellAddress) {
        structural {
            sheet.freezeRows = a.row
            sheet.freezeCols = a.col
        }
    }

    /// Select a whole range with `active` inside it (a click on a header,
    /// a name box entry).
    func select(range: CellRange, active a: CellAddress? = nil) {
        _tabStart = nil
        selectedDrawing = nil
        selection = range
        active = a ?? range.topLeft
        anchor = active
        _extentEnd = range.bottomRight
        _notify(selectionOnly: true)
    }

    /// The far corner of a shift-selection, which arrow keys move.
    private(set) var _extentEnd = CellAddress(row: 0, col: 0)
    /// Where a run of Tabs began: Enter then goes to the next row in that
    /// column, as typing a table row by row in Excel does.
    private var _tabStart: Int? = nil
    /// The picture or chart selected (an index into the sheet's drawings),
    /// instead of cells. Any cell selection clears it.
    var selectedDrawing: Int? = nil
    private var _cf: (sheet: ObjectIdentifier, revision: Int, evaluator: CFEvaluator)? = nil
    private var _dv: (sheet: ObjectIdentifier, revision: Int, rules: [ValidationRule])? = nil

    /// The active sheet's validation rules, read once per state of its data.
    var validationRules: [ValidationRule] {
        let ws = sheet
        if let d = _dv, d.sheet == ObjectIdentifier(ws), d.revision == dataRevision { return d.rules }
        let rules = Validations.rules(ws)
        _dv = (ObjectIdentifier(ws), dataRevision, rules)
        return rules
    }

    /// The active sheet's conditional formats, for one state of its data;
    /// nil when it has none.
    func conditionalFormats() -> CFEvaluator? {
        let ws = sheet
        guard ws.keptElements.contains(where: { $0.name == "conditionalFormatting" }) else { return nil }
        if let c = _cf, c.sheet == ObjectIdentifier(ws), c.revision == dataRevision { return c.evaluator }
        let e = CFEvaluator(rules: ConditionalFormats.rules(ws, theme: book.themeColors), book: book, engine: engine, sheet: activeSheet)
        _cf = (ObjectIdentifier(ws), dataRevision, e)
        return e
    }

    /// Move within a selection with Enter/Tab (Excel keeps a multi-cell
    /// selection and walks the active cell through it).
    func advance(rows dr: Int, cols dc: Int) {
        if selection.isSingle {
            let start = _tabStart
            if dc != 0 {
                select(CellAddress(row: active.row, col: active.col + dc))
                _tabStart = start ?? active.col - dc
            } else {
                select(CellAddress(row: active.row + dr, col: dr > 0 ? start ?? active.col : active.col))
            }
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
        let headers = ws.tables.isEmpty ? [:] : _tableHeaderNames(items.map(\.0), sheet: si)
        var before: [CellAddress: Cell?] = [:]
        for (a, text) in items {
            if before[a] == nil { before[a] = .some(ws.cells[a]) }
            var cell = ws.cells[a] ?? Cell(input: "")
            cell.rawFormula = nil      // what is typed replaces what the file had
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
        if !headers.isEmpty {
            // Renaming a table's column renames the references to it; their
            // cells join this undo step.
            let formulas = book.sheets.enumerated().flatMap { (osi, o) in o.cells.compactMap { $0.value.formula != nil ? (osi, $0.key) : nil } }
            var was: [Int: [CellAddress: Cell?]] = [:]
            for (osi, a) in formulas { was[osi, default: [:]][a] = .some(book.sheets[osi].cells[a]) }
            _renameTableColumns(headers, sheet: si)
            for (osi, cells) in was where osi == si {
                for (a, c) in cells where book.sheets[si].cells[a]?.input != c?.input && before[a] == nil { before[a] = c }
            }
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

    /// `from` is the width before a live drag changed it, so the undo
    /// step restores what was there when the drag began.
    func setColumnWidth(_ col: Int, _ w: Double, from: Double? = nil) {
        if let from { sheet.colWidths[col] = from }
        structural { sheet.colWidths[col] = max(0, w) }
    }

    func setRowHeight(_ row: Int, _ h: Double, from: Double? = nil) {
        if let from { sheet.rowHeights[row] = from }
        structural { sheet.rowHeights[row] = max(0, h) }
    }

    // MARK: Sorting

    /// The ribbon's way to the grid (clipboard, a formula into the editor).
    var onCommand: ((SheetCommand) -> Void)?

    /// The block of data around a cell: the rectangle of filled cells
    /// reachable from it, Excel's "current region".
    func currentRegion(_ a: CellAddress) -> CellRange {
        func filled(_ r: Int, _ c: Int) -> Bool {
            r >= 0 && c >= 0 && !(sheet.cells[CellAddress(row: r, col: c)]?.value.isEmpty ?? true)
        }
        var r = CellRange(a)
        var grew = true
        while grew {
            grew = false
            if r.top > 0, (r.left - 1 ... r.right + 1).contains(where: { filled(r.top - 1, $0) }) { r.top -= 1; grew = true }
            if (r.left - 1 ... r.right + 1).contains(where: { filled(r.bottom + 1, $0) }) { r.bottom += 1; grew = true }
            if r.left > 0, (r.top - 1 ... r.bottom + 1).contains(where: { filled($0, r.left - 1) }) { r.left -= 1; grew = true }
            if (r.top - 1 ... r.bottom + 1).contains(where: { filled($0, r.right + 1) }) { r.right += 1; grew = true }
        }
        return r
    }

    /// Sort the rows of the selection (or of the data around the active
    /// cell) by the active cell's column. A first row of labels over data
    /// stays put, as Excel guesses it. One undo step.
    func sortSelection(ascending: Bool) {
        var r = selection.isSingle ? currentRegion(active) : selection
        let used = sheet.usedExtent
        r = CellRange(top: r.top, left: r.left, bottom: min(r.bottom, used.row), right: min(r.right, used.col))
        guard r.rows > 1 else { return }
        let key = min(max(active.col, r.left), r.right)
        // A header: the first row is all text and the key column below it is not.
        let firstIsText = (r.left ... r.right).allSatisfy { col in
            let v = sheet.value(CellAddress(row: r.top, col: col)); return v.isText || v.isEmpty
        }
        let belowHasNumbers = (r.top + 1 ... r.bottom).contains { sheet.value(CellAddress(row: $0, col: key)).number != nil }
        let top = firstIsText && belowHasNumbers ? r.top + 1 : r.top
        guard r.bottom > top else { return }
        let before = sortRows(CellRange(top: top, left: r.left, bottom: r.bottom, right: r.right), key: key, ascending: ascending)
        if !before.isEmpty { _record(sheet: activeSheet, before: before) }
    }

    /// Reorder the rows of `r` by column `key`, blanks last either way,
    /// shifting formulas with their rows. Returns what the cells were, for
    /// an undo step (empty when the order did not change).
    @discardableResult
    func sortRows(_ r: CellRange, key: Int, ascending: Bool) -> [CellAddress: Cell?] {
        let rowsIdx = Array(r.top ... r.bottom)
        let sorted = rowsIdx.sorted { a, b in
            let va = sheet.value(CellAddress(row: a, col: key)), vb = sheet.value(CellAddress(row: b, col: key))
            if va.isEmpty != vb.isEmpty { return vb.isEmpty }
            let c = CalcEngine.compare(va, vb)
            if c == 0 { return a < b }   // stable
            return ascending ? c < 0 : c > 0
        }
        guard sorted != rowsIdx else { return [:] }
        var before: [CellAddress: Cell?] = [:]
        var moved: [CellAddress: Cell] = [:]
        for (newRow, oldRow) in zip(rowsIdx, sorted) {
            for col in r.left ... r.right {
                let from = CellAddress(row: oldRow, col: col), to = CellAddress(row: newRow, col: col)
                before[to] = .some(sheet.cells[to])
                if var cell = sheet.cells[from] {
                    if let f = cell.formula, newRow != oldRow {
                        let g = Formula.shifted(f, rows: newRow - oldRow, cols: 0)
                        cell.formula = g
                        cell.input = Formula.text(g)
                    }
                    moved[to] = cell
                }
            }
        }
        for a in before.keys { sheet.cells[a] = moved[a] }
        return before
    }

    // MARK: Sheets

    func addSheet() {
        structural {
            book.sheets.insert(Worksheet(name: book.nextSheetName()), at: activeSheet + 1)
            activeSheet += 1
        }
    }

    @discardableResult
    func renameSheet(_ i: Int, _ name: String) -> Bool {
        let n = name.trimmingWhitespace()
        guard !n.isEmpty, n.count <= 31, !n.contains(where: { "[]:*?/\\".contains($0) }) else { return false }
        if let j = book.sheet(named: n), j != i { return false }
        let old = book.sheets[i].name
        guard old != n else { return true }
        structural { _rename(i, old, n) }
        return true
    }

    private func _rename(_ i: Int, _ old: String, _ n: String) {
        book.sheets[i].name = n
        // Formulas, defined names and charts that named the sheet follow it.
        _rewriteFormulas { r, _ in
            var r = r
            if r.sheet?.lowercased() == old.lowercased() { r.sheet = n }
            return r
        }
    }

    func deleteSheet(_ i: Int) {
        guard book.sheets.count > 1 else { return }
        structural {
            let gone = book.sheets[i].name.lowercased()
            book.sheets.remove(at: i)
            // Names that belonged to it go with it; later sheets' move up.
            book.fileNames.removeAll { $0.localSheet == i }
            for k in book.fileNames.indices { if let l = book.fileNames[k].localSheet, l > i { book.fileNames[k].localSheet = l - 1 } }
            // References to the deleted sheet become #REF!, as Excel's do.
            _rewriteFormulas { ref, _ in ref.sheet?.lowercased() == gone ? nil : ref }
            _selections.removeAll()
            let target = min(activeSheet, book.sheets.count - 1)
            if activeSheet != target { activeSheet = target } else { _notify(selectionOnly: true) }
        }
    }

    /// Pass every reference in every formula (and defined name) through
    /// `f`, which gets the reference and the index of the sheet the formula
    /// is on; nil makes it #REF!.
    func _rewriteFormulas(_ f: (FormulaRef, Int) -> FormulaRef?) {
        for (si, ws) in book.sheets.enumerated() {
            for (a, c) in ws.cells {
                guard let expr = c.formula else { continue }
                let g = Formula.mapRefs(expr) { f($0, si) }
                if g != expr {
                    ws.cells[a]?.formula = g
                    ws.cells[a]?.input = Formula.text(g)
                }
            }
        }
        for (k, v) in book.names {
            guard let expr = try? Formula.parse(v) else { continue }
            // A name's references always name their sheet; -1 means "no home sheet".
            let g = Formula.mapRefs(expr) { f($0, -1) }
            if g != expr { book.names[k] = Formula.print(g) }
        }
        // The file's other names (print areas, filter ranges, sheet-local
        // ones) hold references too; a union like a print title's is
        // mapped part by part.
        for i in book.fileNames.indices {
            let parts = book.fileNames[i].text.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let mapped = parts.map { p -> String in
                guard let e = try? Formula.parse("=" + p) else { return p }
                let g = Formula.mapRefs(e) { f($0, -1) }
                return g == e ? p : Formula.print(g)
            }
            if mapped != parts { book.fileNames[i].text = mapped.joined(separator: ",") }
        }
        // The x14 formulas in each sheet's extLst (sparklines, rules).
        for (si, ws) in book.sheets.enumerated() {
            for k in ws.keptElements.indices where ws.keptElements[k].name == "extLst" {
                let text = KeptRefs.shiftExtFormulas(ws.keptElements[k].text) { f($0, si) }
                if text != ws.keptElements[k].text { ws.keptElements[k].text = text }
            }
        }
        // Charts read cells by sheet-qualified references too.
        func map(_ t: String) -> String {
            guard let e = try? Formula.parse("=" + t) else { return t }
            let g = Formula.mapRefs(e) { f($0, -1) }
            return g == e ? t : Formula.print(g)
        }
        for ws in book.sheets {
            for i in ws.drawings.indices {
                guard case .chart(var sc) = ws.drawings[i].kind else { continue }
                let before = sc
                sc.refs = sc.refs.map { (name: $0.name.map(map), cat: $0.cat.map(map), val: $0.val.map(map)) }
                for (k, v) in sc.formulas { sc.formulas[k] = map(v) }
                if sc != before {
                    ws.drawings[i].kind = .chart(sc)
                    ws.drawingsEdited = true
                }
            }
        }
    }

    // MARK: Undo

    /// One undo step: the cells one edit changed, or — for edits that
    /// move things (rows, columns, sheets, sizes) — the sheets before and
    /// after, whole.
    private enum Step {
        case cells(sheet: Int, before: [CellAddress: Cell?], after: [CellAddress: Cell?],
                   selection: CellRange, active: CellAddress)
        case structure(before: _BookState, after: _BookState, selection: CellRange, active: CellAddress)
    }

    struct _BookState {
        let sheets: [Worksheet]
        let names: [String: String]
        let fileNames: [DefinedName]
        let activeSheet: Int
    }

    private var _undo: [Step] = []
    private var _redo: [Step] = []

    var canUndo: Bool { !_undo.isEmpty }
    var canRedo: Bool { !_redo.isEmpty }

    private func _push(_ s: Step) {
        _undo.append(s)
        if _undo.count > 500 { _undo.removeFirst(_undo.count - 500) }
        _redo.removeAll()
        edits += 1
    }

    func _record(sheet si: Int, before: [CellAddress: Cell?], recalc: Bool = true) {
        let ws = book.sheets[si]
        var after: [CellAddress: Cell?] = [:]
        for a in before.keys { after[a] = .some(ws.cells[a]) }
        _push(.cells(sheet: si, before: before, after: after, selection: selection, active: active))
        if recalc { engine.recalculate() }
        _notify()
    }

    /// Widen the last cell step's "before" to `before`, for an edit made
    /// of a change and then setInputs that should undo as one.
    func _foldLastStep(before: [CellAddress: Cell?]) {
        guard case .cells(let si, var b, let after, let sel, let act)? = _undo.last else { return }
        for (a, c) in before { b[a] = c }
        _undo[_undo.count - 1] = .cells(sheet: si, before: b, after: after, selection: sel, active: act)
    }

    private func _bookState() -> _BookState {
        _BookState(sheets: book.sheets.map { $0.copy() }, names: book.names, fileNames: book.fileNames, activeSheet: activeSheet)
    }

    private func _restore(_ s: _BookState) {
        book.sheets = s.sheets.map { $0.copy() }
        book.names = s.names
        book.fileNames = s.fileNames
        _selections.removeAll()
        let target = min(s.activeSheet, book.sheets.count - 1)
        if activeSheet != target { activeSheet = target }
    }

    /// Run an edit that moves things, as one undo step over whole sheets.
    func structural(_ change: () -> Void) {
        let before = _bookState()
        let sel = selection, act = active
        change()
        _push(.structure(before: before, after: _bookState(), selection: sel, active: act))
        engine.recalculate()
        _notify()
    }

    func undo() {
        guard let s = _undo.popLast() else { return }
        switch s {
        case .cells(let si, let before, _, let sel, let act):
            _apply(si, before)
            if activeSheet != si { activeSheet = si }
            selection = sel; active = act
        case .structure(let before, _, let sel, let act):
            _restore(before)
            selection = sel; active = act
        }
        _redo.append(s)
        edits -= 1
        anchor = active
        _extentEnd = selection.bottomRight
        engine.recalculate()
        _notify()
    }

    func redo() {
        guard let s = _redo.popLast() else { return }
        switch s {
        case .cells(let si, _, let after, _, _):
            _apply(si, after)
            if activeSheet != si { activeSheet = si }
        case .structure(_, let after, _, _):
            _restore(after)
        }
        _undo.append(s)
        edits += 1
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

    func _notify(selectionOnly: Bool = false) {
        revision += 1
        if !selectionOnly { dataRevision += 1 }
        notifyListeners()
    }

    /// The status bar's figures for the selection: Sum, Average, Count.
    var selectionStats: (sum: Double, average: Double?, count: Int, numbers: Int) {
        var sum = 0.0, count = 0, numbers = 0
        let r = selection
        let keys: [CellAddress] = r.rows * r.cols <= sheet.cells.count
            ? (r.top ... r.bottom).flatMap { row in (r.left ... r.right).map { CellAddress(row: row, col: $0) } }
            : sheet.cells.keys.filter { r.contains($0) }
        // Rows a filter hid are not counted, as Excel's status bar does not.
        let hidden = sheet.filteredRows
        for a in keys where !hidden.contains(a.row) {
            let v = sheet.value(a)
            if v.isEmpty { continue }
            count += 1
            if let n = v.number { sum += n; numbers += 1 }
        }
        return (sum, numbers > 0 ? sum / Double(numbers) : nil, count, numbers)
    }
}
