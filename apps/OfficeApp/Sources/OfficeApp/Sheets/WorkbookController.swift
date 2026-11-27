// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Every change to a workbook goes through here: typing into cells,
// clearing, formatting, sheets added and renamed. Each is one undo step
// (a list of the cells it changed, before and after), and each ends in a
// recalculation and a notification. The selection lives here too, so the
// grid, the formula bar, the name box and the status bar agree.

import Flutter
import OfficeText
import Foundation

final class WorkbookController: ChangeNotifier {
    private let _leakProbe = LeakProbe("WorkbookController")
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

    var sheet: Worksheet { book.sheets[_sheetOverride ?? activeSheet] }

    /// Sheets selected together (Select All Sheets, Ctrl/Shift-click on a
    /// tab), as Excel's group mode: what is typed or formatted on the
    /// active one goes to each of them at the same cells. Empty when only
    /// the active sheet is selected.
    var groupedSheets: Set<Int> {
        get { Set(book.sheets.indices.filter { book.sheets[$0].tabSelected }) }
        set { for (i, ws) in book.sheets.enumerated() { ws.tabSelected = newValue.contains(i) } }
    }
    private var _sheetOverride: Int?
    var isGrouped: Bool { groupedSheets.count > 1 && groupedSheets.contains(activeSheet) }

    func selectAllSheets() {
        groupedSheets = Set(book.sheets.indices.filter { !book.sheets[$0].hidden })
        _notify(selectionOnly: true)
    }
    func groupSheet(_ i: Int, add: Bool) {
        if add { groupedSheets.insert(activeSheet); groupedSheets.insert(i) } else { groupedSheets = [] }
        _notify(selectionOnly: true)
    }
    func ungroupSheets() {
        guard !groupedSheets.isEmpty else { return }
        groupedSheets = []
        _notify(selectionOnly: true)
    }

    /// Run `edit` on the active sheet and on every grouped one, as ONE undo step.
    private func _groupEdit(_ edit: () -> Void) -> Bool {
        guard isGrouped, _sheetOverride == nil else { return false }
        let before = _bookState()
        let sel = selection, act = active
        let mark = _undo.count
        let edits0 = edits
        for si in groupedSheets.sorted() where si < book.sheets.count {
            _sheetOverride = si
            edit()
        }
        _sheetOverride = nil
        if _undo.count > mark { _undo.removeSubrange(mark...) }
        edits = edits0
        _push(.structure(before: before, after: _bookState(), selection: sel, active: act))
        engine.recalculate()
        _notify()
        return true
    }

    override init() {
        book = Workbook()
        engine = CalcEngine(book)
        super.init()
    }

    /// Replace the workbook (open a file, new workbook).
    func load(_ b: Workbook) {
        book = b
        ExcelDate.system1904 = b.date1904
        engine = CalcEngine(b)
        _selections.removeAll()
        _parseAll()
        engine.recalculate()
        activeSheet = min(max(0, b.activeTab), b.sheets.count - 1)
        // Never open on a hidden sheet.
        if b.sheets[activeSheet].hidden, let first = b.sheets.indices.first(where: { !b.sheets[$0].hidden }) { activeSheet = first }
        active = sheet.savedActive ?? CellAddress(row: 0, col: 0)
        selection = CellRange(active)
        anchor = active
        _extentEnd = active
        _undo.removeAll(); _redo.removeAll()
        edits = 0
        _notify()
    }

    func markSaved() { edits = 0; _notify(selectionOnly: true) }

    /// A workbook restored from a recovery copy: unsaved by definition, whatever the edit count says.
    func markUnsaved() { edits = max(edits, 1); _notify(selectionOnly: true) }

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
        if refuses("formatCells") { return }
        let r = selection
        if let m = sheet.merges.first(where: { $0 == r }) {
            structural { sheet.merges.removeAll { $0 == m } }
            return
        }
        guard !r.isSingle, r.area <= 1_000_000 else { return }
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
    /// View > Zoom: the sheet's zoom in percent. Saved with the sheet.
    func setZoom(percent: Int) { viewChange { sheet.zoomPercent = percent } }

    /// A view setting changed (zoom, headings, gridlines...): not an undo step, as in Excel, but the file is changed and saves it.
    func viewChange(_ change: () -> Void) {
        change()
        markUnsaved()
    }
    /// View > Show: Headings (row numbers and column letters).
    func toggleHeadings() { viewChange { sheet.showHeadings.toggle() } }
    /// View > Show: Gridlines.
    func toggleGridlines() { viewChange { sheet.showGridlines.toggle() } }
    /// Formulas > Show Formulas (Ctrl+`).
    func toggleShowFormulas() { viewChange { sheet.showFormulas.toggle() } }
    /// Page Layout > Sheet Right-to-Left.
    func toggleRightToLeft() { viewChange { sheet.rightToLeft.toggle() } }

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
    var selectedDrawing: Int? = nil {
        didSet {
            // The others picked along with it last only while one stays selected (and never include the selected one).
            if selectedDrawing == nil { alsoSelectedDrawings = [] } else if let s = selectedDrawing { alsoSelectedDrawings.remove(s) }
        }
    }
    /// The charts and pictures picked in addition to the selected one (Shift-click, or a tap with Select Multiple on).
    private(set) var alsoSelectedDrawings: Set<Int> = []
    /// A finger has no Shift: while this is on, a tap on a chart or picture adds it to the selection or takes it out.
    var selectMultiple = false
    /// Every selected chart and picture, in sheet order.
    var selectedDrawingIndexes: [Int] { (selectedDrawing.map { [$0] } ?? []) + alsoSelectedDrawings.sorted() }

    /// Select one chart or picture. One already among the selected keeps the group (a press on it is about to move them all)
    /// unless `keepingGroup` is off, as a plain tap on one of several selects just that one.
    func selectDrawing(_ index: Int, keepingGroup: Bool = false) {
        if keepingGroup, selectedDrawingIndexes.contains(index) { return }
        alsoSelectedDrawings = []
        selectedDrawing = index
    }

    /// A tap or Shift-click on a drawing while picking several: selects it if nothing is selected; otherwise adds it to the
    /// selection, or takes it out (when the selected one is taken out, another picked one becomes the selected one).
    func toggleDrawingPick(_ index: Int) {
        guard sheet.drawings.indices.contains(index), sheet.drawings[index].kind != .other else { return }
        guard let main = selectedDrawing else { selectedDrawing = index; _notify(selectionOnly: true); return }
        if index == main {
            guard let next = alsoSelectedDrawings.min() else { return }
            alsoSelectedDrawings.remove(next)
            selectedDrawing = next
        } else if alsoSelectedDrawings.contains(index) {
            alsoSelectedDrawings.remove(index)
        } else {
            alsoSelectedDrawings.insert(index)
        }
        _notify(selectionOnly: true)
    }
    /// Format Painter, armed: the cells whose formats the next selection takes.
    var painterSource: (sheet: Int, range: CellRange)? = nil
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
            if fmt.containsSubstring("%") { return NumberFormat.full(n * 100) + "%" }
            if NumberFormat.format(n, fmt).text != NumberFormat.general(n), fmt.lowercased().containsSubstring("y") || fmt.lowercased().containsSubstring("d") {
                return NumberFormat.format(n, fmt.containsSubstring("h") ? "m/d/yyyy h:mm:ss AM/PM" : "m/d/yyyy").text
            }
            // A time of day as Excel's bar shows it, 12:30:00 PM — not 0.520833333333333.
            if n >= 0, n < 1, NumberFormat.isDateTime(fmt), !fmt.containsSubstring("[") {
                return NumberFormat.format(n, "h:mm:ss AM/PM").text
            }
            return NumberFormat.full(n)
        }
        return c.input
    }

    /// Type `text` into `a` (Enter in the cell or the formula bar).
    func setInput(_ text: String, at a: CellAddress) {
        setInputs([(a, text)])
    }

    /// Something typed in the row just below a table, or the column just
    /// right of it, joins the table, as Excel's AutoCorrect has it ("include
    /// new rows and columns in table"): the banding and the structured
    /// references follow. Its own undo step, so the first ⌘Z takes back the
    /// growth and leaves the entry, as in Excel. Not past a totals row, and
    /// not into another table.
    func growTable(toInclude a: CellAddress) {
        let ws = sheet
        guard !(ws.cells[a]?.value.isEmpty ?? true) else { return }
        for (i, t) in ws.tables.enumerated() {
            var r = t.ref
            let below = !t.totalsRow && a.row == r.bottom + 1 && a.col >= r.left && a.col <= r.right
            let right = a.col == r.right + 1 && a.row >= r.top && a.row <= r.bottom
            guard below || right else { continue }
            if below { r.bottom += 1 } else { r.right += 1 }
            let added = below ? CellRange(top: r.bottom, left: r.left, bottom: r.bottom, right: r.right)
                              : CellRange(top: r.top, left: r.right, bottom: r.bottom, right: r.right)
            guard !ws.tables.enumerated().contains(where: { $0.offset != i && $0.element.ref.intersects(added) }),
                  !ws.merges.contains(where: { $0.intersects(added) }) else { return }
            structural {
                ws.tables[i].ref = r
                if right { ws.tables[i].columnIds.append(nil) }
                ws.tables[i].edited = true
            }
            return
        }
    }

    /// The format Excel gives a formula typed into a General cell: a date
    /// for TODAY() and DATE(…), date and time for NOW(), a time for TIME(…);
    /// and the format of the first cell it reads when that is a date (on
    /// + and −) or money — =A1+7 on a date is a date, =B2*C2 on dollars is
    /// dollars. Without it TODAY() showed 46309.
    func _impliedFormat(_ f: FormulaExpr, _ ws: Worksheet) -> String? {
        func cellFormat(_ r: FormulaRef) -> String? {
            guard r.start.row != nil, r.start.col != nil else { return nil }
            let target = r.sheet.flatMap { n in book.sheets.first { $0.name.lowercased() == n.lowercased() } } ?? ws
            let a = r.range.topLeft
            return book.style(target.cells[a]?.style ?? target.defaultStyle(at: a)).numberFormat
        }
        func walk(_ e: FormulaExpr, dates: Bool) -> String? {
            switch e {
            case .paren(let x), .negate(let x), .plus(let x): return walk(x, dates: dates)
            case .ref(let r):
                guard let fmt = cellFormat(r), fmt != "General" else { return nil }
                if NumberFormat.isDateTime(fmt) { return dates ? fmt : nil }
                return fmt.containsSubstring("$") || fmt.containsSubstring("€") || fmt.containsSubstring("£") ? fmt : nil
            case .binary(let op, let l, let r):
                switch op {
                case .add, .sub: return walk(l, dates: dates) ?? walk(r, dates: dates)
                case .mul, .div: return walk(l, dates: false) ?? walk(r, dates: false)
                default: return nil
                }
            case .call(let name, let args):
                switch name.uppercased() {
                case "TODAY", "DATE", "DATEVALUE", "EDATE", "EOMONTH", "WORKDAY", "WORKDAY.INTL": return "m/d/yyyy"
                case "NOW": return "m/d/yyyy h:mm"
                case "TIME", "TIMEVALUE": return "h:mm AM/PM"
                case "SUM", "AVERAGE", "MIN", "MAX", "MEDIAN", "ROUND", "ROUNDUP", "ROUNDDOWN", "ABS":
                    return args.first.flatMap { walk($0, dates: name.uppercased() != "SUM") }
                default: return nil
                }
            default: return nil
            }
        }
        return walk(f, dates: true)
    }

    /// Several cells in one step (paste, fill, Ctrl+Enter).
    func setInputs(_ items: [(CellAddress, String)], sheet si: Int? = nil) {
        if si == nil, _groupEdit({ setInputs(items) }) { return }
        let si = si ?? _sheetOverride ?? activeSheet
        if refusesEdit(items.map(\.0), sheet: si) { return }
        let ws = book.sheets[si]
        let headers = ws.tables.isEmpty ? [:] : _tableHeaderNames(items.map(\.0), sheet: si)
        var before: [CellAddress: Cell?] = [:]
        for (a, text) in items {
            if before[a] == nil { before[a] = .some(ws.cells[a]) }
            var cell = ws.cells[a] ?? Cell(input: "")
            if ws.cells[a] == nil, !text.isEmpty { cell.style = ws.defaultStyle(at: a) }   // a formatted row or column's style
            cell.rawFormula = nil      // what is typed replaces what the file had
            cell.keptAttrs = [:]
            if text.isEmpty {
                if cell.style == 0 { ws.cells[a] = nil; continue }
                cell.input = ""; cell.formula = nil; cell.value = .empty
                ws.cells[a] = cell
                continue
            }
            cell.input = text
            // A line break in what was typed turns Wrap Text on, as Excel
            // does, so the lines show as lines.
            if text.containsSubstring("\n"), !text.hasPrefix("="), !book.style(cell.style).wrap {
                var st = book.style(cell.style)
                st.wrap = true
                cell.style = book.styleIndex(st)
            }
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
                    let f = try Formula.parse(text)
                    cell.formula = f
                    cell.dynamic = true          // as in Excel 365: an array result spills
                    cell.value = .empty
                    if book.style(cell.style).numberFormat == "General", let fmt = _impliedFormat(f, ws) {
                        var st = book.style(cell.style)
                        st.numberFormat = fmt
                        cell.style = book.styleIndex(st)
                    }
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
        if refuses("formatCells") { return }
        if _groupEdit({ setStyle(change, range: range) }) { return }
        let r = range ?? selection
        let ws = sheet
        // Whole rows or columns: the format goes on the row or column, as
        // Excel keeps it (<row s=…>, <col style=…>), so cells typed there
        // later take it — not into a cell for every column of a row, which
        // made a bold header row 16,384 cells and a 44 KB file.
        let wholeRows = r.left == 0 && r.right >= CellAddress.maxCols - 1
        let wholeCols = r.top == 0 && r.bottom >= CellAddress.maxRows - 1
        if wholeRows || wholeCols {
            structural {
                if wholeCols {
                    var c = r.left
                    while c <= r.right {
                        let old = ws.colStyle(c) ?? 0
                        var st = book.style(old)
                        change(&st)
                        let new = book.styleIndex(st)
                        var hi = c
                        while hi < r.right, (ws.colStyle(hi + 1) ?? 0) == old { hi += 1 }
                        ws.colAttrRuns.append((c, hi, ["style": String(new)]))
                        c = hi + 1
                    }
                }
                // A formatted row outranks its columns, so on the whole
                // sheet the rows already formatted change too (and only
                // those: not a million rows each given a style).
                let rowsToStyle = !wholeRows ? []
                    : wholeCols ? ws.rowAttrs.keys.filter { ws.rowStyle($0) != nil }
                    : Array(r.top ... r.bottom)
                for row in rowsToStyle {
                    var st = book.style(ws.rowStyle(row) ?? 0)
                    change(&st)
                    ws.rowAttrs[row, default: [:]]["s"] = String(book.styleIndex(st))
                    ws.rowAttrs[row]?["customFormat"] = "1"
                }
                // Columns (not the whole sheet) crossing a formatted row: the
                // row's format outranks the column's there, so the crossing
                // gets a cell of its own, as Excel writes it — else a bold
                // header row kept D1 bold and ⌘B on column D never took.
                if wholeCols && !wholeRows {
                    for row in ws.rowAttrs.keys where ws.rowStyle(row) != nil {
                        for col in r.left ... r.right where ws.cells[CellAddress(row: row, col: col)] == nil {
                            var cell = Cell(input: "")
                            cell.style = ws.rowStyle(row)!
                            ws.cells[CellAddress(row: row, col: col)] = cell
                        }
                    }
                }
                for a in ws.cells.keys where r.contains(a) {
                    var st = book.style(ws.cells[a]!.style)
                    change(&st)
                    ws.cells[a]!.style = book.styleIndex(st)
                }
            }
            return
        }
        var before: [CellAddress: Cell?] = [:]
        // Formatting a huge range (a whole column) touches only cells that exist
        // plus the visible block the user selected; Excel stores column styles,
        // which arrive with .xlsx in X2.
        let area = r.area
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
        _record(sheet: _sheetOverride ?? activeSheet, before: before, recalc: false)
    }

    /// Bold, italic, wrap… on a selection: every cell gets the opposite of
    /// the active cell's, as Excel does — not each cell flipped on its own,
    /// which turned a half-bold selection inside out.
    func toggleStyle(_ key: WritableKeyPath<CellStyle, Bool>) {
        let on = !style(at: active)[keyPath: key]
        setStyle { $0[keyPath: key] = on }
    }

    /// Left, centre, right: on, or back to General when the active cell
    /// already has it.
    func toggleAlign(_ a: CellStyle.HAlign) {
        let to: CellStyle.HAlign = style(at: active).hAlign == a ? .general : a
        setStyle { $0.hAlign = to }
    }

    /// An empty cell in a formatted row or column shows its format.
    func style(at a: CellAddress) -> CellStyle { book.style(sheet.cells[a]?.style ?? sheet.defaultStyle(at: a)) }

    /// `from` is the width before a live drag changed it, so the undo
    /// step restores what was there when the drag began.
    func setColumnWidth(_ col: Int, _ w: Double, from: Double? = nil) {
        if let from { sheet.colWidths[col] = from }
        structural { sheet.colWidths[col] = max(0, w); sheet.widenedCols.remove(col) }
    }

    func setRowHeight(_ row: Int, _ h: Double, from: Double? = nil) {
        if let from { sheet.rowHeights[row] = from }
        structural { sheet.rowHeights[row] = max(0, h); sheet.fittedRows.remove(row) }
    }

    // MARK: Sorting

    /// The ribbon's way to the grid (clipboard, a formula into the editor).
    var onCommand: ((SheetCommand) -> Void)?
    /// Asks the user about an entry its validation rule objects to; the shell answers through the
    /// callback. Unset (tests, headless): the entry is handled by the rule's style alone.
    var onValidationAlert: ((ValidationAlert, @escaping (ValidationChoice) -> Void) -> Void)?
    /// Data → Circle Invalid Data is on: cells breaking their rule are ringed until it is cleared.
    var circlesOn = false
    var circleCache: (edits: Int, cells: [CellAddress])?

    /// The block of data around a cell: the rectangle of filled cells
    /// reachable from it, Excel's "current region".
    func currentRegion(_ a: CellAddress) -> CellRange {
        func filled(_ r: Int, _ c: Int) -> Bool {
            r >= 0 && c >= 0 && !(sheet.cells[CellAddress(row: r, col: c)]?.value.isEmpty ?? true)
        }
        // (Each side grows as far as it can before the next is tried, so a tall table costs one pass down its
        // rows and a check of each side column per pass, not a scan of the whole height for every row added:
        // with a screen reader on, one edit of a 50,000-row table took 1,172 s (debug build) to name the active cell's
        // header. The region is the same, the smallest range no filled cell touches from outside, corners included.)
        var r = CellRange(a)
        var grew = true
        while grew {
            grew = false
            while r.top > 0, (r.left - 1 ... r.right + 1).contains(where: { filled(r.top - 1, $0) }) { r.top -= 1; grew = true }
            while (r.left - 1 ... r.right + 1).contains(where: { filled(r.bottom + 1, $0) }) { r.bottom += 1; grew = true }
            while r.left > 0, (r.top - 1 ... r.bottom + 1).contains(where: { filled($0, r.left - 1) }) { r.left -= 1; grew = true }
            while (r.top - 1 ... r.bottom + 1).contains(where: { filled($0, r.right + 1) }) { r.right += 1; grew = true }
        }
        return r
    }

    /// Sort the rows of the selection (or of the data around the active
    /// cell) by the active cell's column. A first row of labels over data
    /// stays put, as Excel guesses it. One undo step.
    func sortSelection(ascending: Bool) {
        if refuses("sort") { return }
        guard let g = sortRegion() else { return }
        let key = min(max(active.col, g.range.left), g.range.right)
        let top = g.hasHeader ? g.range.top + 1 : g.range.top
        guard g.range.bottom > top else { return }
        let data = CellRange(top: top, left: g.range.left, bottom: g.range.bottom, right: g.range.right)
        structural {
            sortRows(data, key: key, ascending: ascending)
            _noteSortState(data, keys: [SortKey(col: key, ascending: ascending)], byColumns: false, caseSensitive: false)
        }
    }

    /// The cells a sort would cover (the selection, or the data around the active cell, cut to
    /// what is used) and whether its first row looks like labels over data, as Excel guesses.
    func sortRegion() -> (range: CellRange, hasHeader: Bool)? {
        var r = selection.isSingle ? currentRegion(active) : selection
        let used = sheet.usedExtent
        r = CellRange(top: r.top, left: r.left, bottom: min(r.bottom, used.row), right: min(r.right, used.col))
        guard r.rows > 1 else { return nil }
        // A header: the first row is all text and differs from what is under it — numbers below
        // in some column, or the first row bold over a plain second one.
        let firstIsText = (r.left ... r.right).allSatisfy { col in
            let v = sheet.value(CellAddress(row: r.top, col: col)); return v.isText || v.isEmpty
        }
        let belowHasNumbers = (r.top + 1 ... r.bottom).contains { row in
            (r.left ... r.right).contains { sheet.value(CellAddress(row: row, col: $0)).number != nil }
        }
        let boldOverPlain = (r.left ... r.right).contains { col in
            !sheet.value(CellAddress(row: r.top, col: col)).isEmpty
                && book.style(sheet.cells[CellAddress(row: r.top, col: col)]?.style ?? 0).bold
                && !book.style(sheet.cells[CellAddress(row: r.top + 1, col: col)]?.style ?? 0).bold
        }
        return (r, firstIsText && (belowHasNumbers || boldOverPlain))
    }

    /// Reorder the rows of `r` by column `key`, blanks last either way,
    /// shifting formulas with their rows. Returns what the cells were, for
    /// an undo step (empty when the order did not change).
    @discardableResult
    func sortRows(_ r: CellRange, key: Int, ascending: Bool) -> [CellAddress: Cell?] {
        sortRows(r, keys: [SortKey(col: key, ascending: ascending)])
    }

    /// The same by several columns: the first decides, the next break its ties. `byColumns` reorders
    /// columns by the values of rows instead (a key's `col` is then a row number).
    @discardableResult
    func sortRows(_ r: CellRange, keys: [SortKey], byColumns: Bool = false, caseSensitive: Bool = false) -> [CellAddress: Cell?] {
        // `line` runs along the sorted axis, `other` across it.
        func addr(_ line: Int, _ other: Int) -> CellAddress { byColumns ? CellAddress(row: other, col: line) : CellAddress(row: line, col: other) }
        let lines = byColumns ? Array(r.left ... r.right) : Array(r.top ... r.bottom)
        let across = byColumns ? Array(r.top ... r.bottom) : Array(r.left ... r.right)
        func matches(_ a: CellAddress, _ k: SortKey) -> Bool {
            let st = book.style(sheet.cells[a]?.style ?? sheet.defaultStyle(at: a))
            let have = (k.on == .cellColor ? st.fill : st.color).map { $0 & 0xFFFFFF }
            return have == k.color.map { $0 & 0xFFFFFF }
        }
        func rank(_ v: CellValue, _ list: [String]) -> Int? {
            guard case .text(let t) = v else { return nil }
            return list.firstIndex { $0.lowercased() == t.lowercased() }
        }
        let sorted = lines.sorted { a, b in
            for k in keys {
                let aa = addr(a, k.col), ab = addr(b, k.col)
                if k.on != .values {
                    let ma = matches(aa, k), mb = matches(ab, k)
                    if ma != mb { return ma == k.colorOnTop }
                    continue
                }
                let va = sheet.value(aa), vb = sheet.value(ab)
                if va.isEmpty != vb.isEmpty { return vb.isEmpty }
                if let list = k.custom {
                    let ra = rank(va, list), rb = rank(vb, list)
                    if ra != rb {
                        // In the list before out of it, whatever the direction; in the list by its order.
                        guard let x = ra else { return false }
                        guard let y = rb else { return true }
                        return k.ascending ? x < y : x > y
                    }
                    if ra != nil { continue }
                }
                var c = CalcEngine.compare(va, vb)
                if c == 0, caseSensitive, case .text(let x) = va, case .text(let y) = vb, x != y {
                    c = x.lowercased() == y.lowercased() ? (x > y ? -1 : 1) : 0   // lower case first
                }
                if c != 0 { return k.ascending ? c < 0 : c > 0 }
            }
            return a < b   // stable
        }
        guard sorted != lines else { return [:] }
        var before: [CellAddress: Cell?] = [:]
        var moved: [CellAddress: Cell] = [:]
        for (newLine, oldLine) in zip(lines, sorted) {
            for o in across {
                let from = addr(oldLine, o), to = addr(newLine, o)
                before[to] = .some(sheet.cells[to])
                if var cell = sheet.cells[from] {
                    if let f = cell.formula, newLine != oldLine {
                        let g = byColumns ? Formula.shifted(f, rows: 0, cols: newLine - oldLine) : Formula.shifted(f, rows: newLine - oldLine, cols: 0)
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
        if _structureLocked() { return }
        structural { _insertFreshSheet() }
    }

    /// A new sheet after the active one, made active (no undo step of its own).
    func _insertFreshSheet() {
        do {
            let at = activeSheet + 1
            let fresh = Worksheet(name: book.nextSheetName())
            // Its columns are counted in the workbook's default font, as the others'.
            fresh.digitWidth = book.digitWidth
            fresh.defaultColWidthPt = ((8 * fresh.digitWidth + 5) / 8).rounded(.up) * 8 * 0.75
            book.sheets.insert(fresh, at: at)
            // Sheet-local names (print areas…) of the sheets after it move along.
            for k in book.fileNames.indices { if let l = book.fileNames[k].localSheet, l >= at { book.fileNames[k].localSheet = l + 1 } }
            activeSheet = at
        }
    }

    private func _structureLocked() -> Bool {
        guard book.structureLocked else { return false }
        onCommand?(.status("The workbook's structure is protected: sheets cannot be added, removed, renamed or hidden."))
        return true
    }

    /// Sheets the tab bar shows.
    var visibleSheets: [Int] { book.sheets.indices.filter { !book.sheets[$0].hidden } }

    func hideSheet(_ i: Int) {
        guard !_structureLocked(), visibleSheets.count > 1, !book.sheets[i].hidden else {
            if visibleSheets.count <= 1 { onCommand?(.status("A workbook must keep at least one visible sheet.")) }
            return
        }
        structural {
            book.sheets[i].hidden = true
            if activeSheet == i { activeSheet = visibleSheets.first ?? 0 }
        }
    }

    func unhideSheet(_ i: Int) {
        guard !_structureLocked(), book.sheets[i].hidden else { return }
        structural {
            book.sheets[i].hidden = false
            book.sheets[i].veryHidden = false
            activeSheet = i
        }
    }

    @discardableResult
    func renameSheet(_ i: Int, _ name: String) -> Bool {
        if _structureLocked() { return true }
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

    /// The sheet a Delete Sheet asked for and is waiting on the user's word (Excel asks when the sheet holds anything).
    /// A refusal the shell shows once (then clears).
    var chartNotice: String?
    private(set) var pendingSheetDelete: Int? = nil

    /// Whether deleting sheet `i` throws something away: cells, charts, pictures or shapes.
    func sheetHasContent(_ i: Int) -> Bool {
        guard book.sheets.indices.contains(i) else { return false }
        let ws = book.sheets[i]
        return !ws.cells.isEmpty || !ws.drawings.isEmpty || !ws.objects.isEmpty
    }

    /// Delete Sheet from a menu: an empty sheet goes at once; one with content waits for `confirmSheetDelete`.
    func requestDeleteSheet(_ i: Int) {
        guard book.sheets.count > 1, book.sheets.indices.contains(i) else { return }
        if sheetHasContent(i) { pendingSheetDelete = i; _notify(selectionOnly: true) } else { deleteSheet(i) }
    }

    func confirmSheetDelete() {
        guard let i = pendingSheetDelete else { return }
        pendingSheetDelete = nil
        deleteSheet(i)
    }

    func cancelSheetDelete() {
        guard pendingSheetDelete != nil else { return }
        pendingSheetDelete = nil
        _notify(selectionOnly: true)
    }

    func deleteSheet(_ i: Int) {
        if _structureLocked() { return }
        guard book.sheets.count > 1, visibleSheets.count > 1 || book.sheets[i].hidden else { return }
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
        // Pivot tables: where each sits, and the cells its cache was built from.
        for ws in book.sheets {
            for i in ws.pivots.indices {
                if let src = ws.pivots[i].source, let e = try? Formula.parse("=" + src) {
                    let g = Formula.mapRefs(e) { f($0, -1) }
                    if g != e { ws.pivots[i].source = Formula.print(g) }
                }
            }
        }
        for (si, ws) in book.sheets.enumerated() {
            for i in ws.pivots.indices {
                guard let e = try? Formula.parse("=" + ws.pivots[i].ref.a1) else { continue }
                let g = Formula.mapRefs(e) { f($0, si) }
                if g != e, let r = CellRange(Formula.print(g).replacingAll("$", with: "")) { ws.pivots[i].ref = r }
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
                sc.seriesEdit = sc.seriesEdit.map { $0.map { ChartSeriesRef(source: $0.source, name: $0.name.map(map), cat: $0.cat.map(map), val: $0.val.map(map)) } }
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
        var isStructure: Bool { if case .structure = self { return true } else { return false } }
    }

    struct _BookState {
        let sheets: [Worksheet]
        let names: [String: String]
        let fileNames: [DefinedName]
        let activeSheet: Int
        var workbookProtection: [String: String]? = nil
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
        if recalc {
            // Values only: recompute what reads them. A formula typed, changed
            // or removed: the dependencies themselves changed, so everything.
            let formulasChanged = before.contains { a, c in (c ?? nil)?.formula != ws.cells[a]?.formula }
            engine.recalculate(changed: Array(before.keys), sheet: si, formulasChanged: formulasChanged)
        }
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
        _BookState(sheets: book.sheets.map { $0.copy() }, names: book.names, fileNames: book.fileNames, activeSheet: activeSheet, workbookProtection: book.workbookProtection)
    }

    private func _restore(_ s: _BookState) {
        book.sheets = s.sheets.map { $0.copy() }
        book.names = s.names
        book.fileNames = s.fileNames
        book.workbookProtection = s.workbookProtection
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
        guard let s = _undo.popLast() else { ScreenReader.announce("Nothing to undo"); return }
        ScreenReader.announce(s.isStructure ? "Undo row or column change" : "Undo cell edit")
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
        guard let s = _redo.popLast() else { ScreenReader.announce("Nothing to redo"); return }
        ScreenReader.announce(s.isStructure ? "Redo row or column change" : "Redo cell edit")
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

    /// View > Page Break Preview: show where the pages are cut (view state, not saved, not undoable).
    var breakPreview = false
    private var _announcedSelection = ""
    func _notify(selectionOnly: Bool = false) {
        // Tell a screen reader where the selection went ("Selected B3", "Selected B3 to C5").
        if ScreenReader.isListening {
            let spoken = selection.area > 1
                ? "Selected \(selection.topLeft.a1) to \(selection.bottomRight.a1)" : SheetsAccessibility.spoken(active, in: self)
            if spoken != _announcedSelection { _announcedSelection = spoken; ScreenReader.announce(spoken) }
        }
        revision += 1
        if !selectionOnly { dataRevision += 1 }
        notifyListeners()
    }

    /// The status bar's figures for the selection: Sum, Average, Count.
    var selectionStats: (sum: Double, average: Double?, count: Int, numbers: Int) {
        var sum = 0.0, count = 0, numbers = 0
        let r = selection
        let keys: [CellAddress] = r.area <= sheet.cells.count
            ? (r.top ... r.bottom).flatMap { row in (r.left ... r.right).map { CellAddress(row: row, col: $0) } }
            : sheet.cells.keys.filter { r.contains($0) }
        // Rows a filter hid are not counted, as Excel's status bar does not.
        let hidden = sheet.filteredRows.union(sheet.hiddenRows)
        for a in keys where !hidden.contains(a.row) {
            let v = sheet.value(a)
            if v.isEmpty { continue }
            count += 1
            if let n = v.number { sum += n; numbers += 1 }
        }
        return (sum, numbers > 0 ? sum / Double(numbers) : nil, count, numbers)
    }
}
