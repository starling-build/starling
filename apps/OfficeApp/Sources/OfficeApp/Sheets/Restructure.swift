// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Edits that move cells: inserting and deleting rows and columns, filling,
// copying and pasting within the workbook, cutting and moving. Each
// rewrites the formulas that point at what moved, on every sheet, the way
// Excel does — references follow their cells, a range grows when rows are
// inserted inside it, and a reference whose cells were deleted becomes
// #REF!.

import Foundation

extension WorkbookController {
    enum Axis { case rows, cols }

    // MARK: Insert and delete

    /// Insert `count` blank rows (or columns) before `index` on the active sheet.
    func insert(_ axis: Axis, at index: Int, count: Int = 1) {
        if refuses(axis == .rows ? "insertRows" : "insertColumns") { return }
        guard count > 0 else { return }
        structural { _shift(axis, at: index, by: count) }
    }

    /// Delete `count` rows (or columns) starting at `index` on the active sheet.
    func delete(_ axis: Axis, at index: Int, count: Int = 1) {
        if refuses(axis == .rows ? "deleteRows" : "deleteColumns") { return }
        guard count > 0 else { return }
        structural { _shift(axis, at: index, by: -count) }
    }

    /// Insert or delete whole rows/columns covering the selection.
    func insertAtSelection(_ axis: Axis) {
        let r = selection
        axis == .rows ? insert(.rows, at: r.top, count: r.rows) : insert(.cols, at: r.left, count: r.cols)
    }

    func deleteAtSelection(_ axis: Axis) {
        let r = selection
        axis == .rows ? delete(.rows, at: r.top, count: r.rows) : delete(.cols, at: r.left, count: r.cols)
    }

    /// Move everything at or past `index` by `delta` (negative deletes the
    /// `-delta` rows/columns starting at `index`).
    private func _shift(_ axis: Axis, at index: Int, by delta: Int) {
        let si = activeSheet
        let ws = sheet
        let deleteEnd = delta < 0 ? index - delta : index    // exclusive
        let limit = axis == .rows ? CellAddress.maxRows : CellAddress.maxCols
        func moved(_ i: Int) -> Int? {
            if delta > 0 { return i >= index ? (i + delta < limit ? i + delta : nil) : i }
            if i < index { return i }
            if i < deleteEnd { return nil }
            return i + delta
        }
        // Cells.
        var cells: [CellAddress: Cell] = [:]
        for (a, c) in ws.cells {
            let i = axis == .rows ? a.row : a.col
            guard let j = moved(i) else { continue }
            cells[axis == .rows ? CellAddress(row: j, col: a.col) : CellAddress(row: a.row, col: j)] = c
        }
        ws.cells = cells
        // Sizes.
        func remap(_ d: [Int: Double]) -> [Int: Double] {
            var out: [Int: Double] = [:]
            for (i, v) in d { if let j = moved(i) { out[j] = v } }
            return out
        }
        if axis == .rows { ws.rowHeights = remap(ws.rowHeights); ws.hiddenRows = Set(ws.hiddenRows.compactMap(moved)) } else { ws.colWidths = remap(ws.colWidths); ws.colWidthChars = remap(ws.colWidthChars) }
        // Rows' and columns' own formats and outline levels go with them.
        if axis == .rows {
            var out: [Int: [String: String]] = [:]
            for (i, v) in ws.rowAttrs { if let j = moved(i) { out[j] = v } }
            ws.rowAttrs = out
        } else {
            ws.colAttrRuns = ws.colAttrRuns.compactMap { r in
                _adjustSpan(r.lo, r.hi, index: index, delta: delta).map { ($0.0, min($0.1, CellAddress.maxCols - 1), r.attrs) }
            }
        }
        // Merges: shifted, shrunk, or gone.
        ws.merges = ws.merges.compactMap { m in
            let (lo, hi) = axis == .rows ? (m.top, m.bottom) : (m.left, m.right)
            guard let (a, b) = _adjustSpan(lo, hi, index: index, delta: delta) else { return nil }
            let r = axis == .rows ? CellRange(top: a, left: m.left, bottom: b, right: m.right)
                                  : CellRange(top: m.top, left: a, bottom: m.bottom, right: b)
            return r.isSingle ? nil : r
        }
        // The filter: its range like a merge's, its hidden rows and its
        // column criteria moved with what they belong to.
        if var af = ws.autoFilter {
            let r = af.range
            let span = axis == .rows ? _adjustSpan(r.top, r.bottom, index: index, delta: delta)
                                     : _adjustSpan(r.left, r.right, index: index, delta: delta)
            if let (lo, hi) = span, !(axis == .rows && moved(r.top) == nil) {
                af.range = axis == .rows ? CellRange(top: lo, left: r.left, bottom: hi, right: r.right)
                                         : CellRange(top: r.top, left: lo, bottom: r.bottom, right: hi)
                if axis == .cols {
                    var cols: [Int: Set<String>] = [:]
                    for (c, v) in af.columns { if let j = moved(c) { cols[j] = v } }
                    af.columns = cols
                }
                af.raw = nil
                ws.autoFilter = af
            } else {
                ws.autoFilter = nil   // its header row or every column went
            }
            ws.filteredRows = ws.autoFilter == nil || axis == .cols ? (ws.autoFilter == nil ? [] : ws.filteredRows)
                                                                    : Set(ws.filteredRows.compactMap(moved))
        }
        // Pictures and charts move and size with their cells.
        func shift(_ m: SheetMarker) -> SheetMarker {
            var m = m
            let i = axis == .rows ? m.row : m.col
            var j = i
            var cut = false
            if delta > 0 { j = i >= index ? min(limit - 1, i + delta) : i }
            else if i >= index { if i < deleteEnd { j = index; cut = true } else { j = i + delta } }
            if axis == .rows { m.row = j; if cut { m.rowOff = 0 } } else { m.col = j; if cut { m.colOff = 0 } }
            return m
        }
        for i in ws.drawings.indices {
            let old = ws.drawings[i].anchor
            switch old {
            case .twoCell(let from, let to): ws.drawings[i].anchor = .twoCell(from: shift(from), to: shift(to))
            case .oneCell(let from, let w, let h): ws.drawings[i].anchor = .oneCell(from: shift(from), width: w, height: h)
            case .absolute: break
            }
            if ws.drawings[i].anchor != old { ws.drawingsEdited = true }
        }
        // Tables: their range moves like a merge's; a column inserted inside
        // gets a new entry, a deleted one loses its own. A table whose header
        // row is deleted goes the way Excel's does — it is kept, one row down.
        for t in ws.tables.indices {
            var table = ws.tables[t]
            let r = table.ref
            let lo0 = axis == .rows ? r.top : r.left, hi0 = axis == .rows ? r.bottom : r.right
            guard let (lo, hi) = _adjustSpan(lo0, hi0, index: index, delta: delta) else { continue }
            if axis == .cols {
                if delta > 0, index > r.left, index <= r.right {
                    table.columnIds.insert(contentsOf: Array(repeating: nil, count: delta), at: index - r.left)
                } else if delta < 0 {
                    let a = max(index, r.left) - r.left, b = min(deleteEnd, r.right + 1) - r.left
                    if a < b { table.columnIds.removeSubrange(a ..< b) }
                }
            }
            table.ref = axis == .rows ? CellRange(top: lo, left: r.left, bottom: hi, right: r.right)
                                      : CellRange(top: r.top, left: lo, bottom: r.bottom, right: hi)
            if table != ws.tables[t] { table.edited = true; ws.tables[t] = table }
        }
        // Notes go with their cells; one whose cell was deleted goes too.
        for n in ws.notes.indices {
            guard let a = ws.notes[n].at else { continue }
            let i = axis == .rows ? a.row : a.col
            ws.notes[n].at = moved(i).map { axis == .rows ? CellAddress(row: $0, col: a.col) : CellAddress(row: a.row, col: $0) }
        }
        // Kept elements that name cells: conditional formats, validations…
        let sheetName = ws.name.lowercased()
        ws.keptElements = ws.keptElements.compactMap { e in
            guard KeptRefs.elements.contains(e.name) else { return e }
            let text = KeptRefs.shift(e.name, e.text, range: { r in
                guard let (lo, hi) = axis == .rows ? self._adjustSpan(r.top, r.bottom, index: index, delta: delta)
                                                   : self._adjustSpan(r.left, r.right, index: index, delta: delta) else { return nil }
                return axis == .rows ? CellRange(top: lo, left: r.left, bottom: hi, right: r.right)
                                     : CellRange(top: r.top, left: lo, bottom: r.bottom, right: hi)
            }, ref: { ref in
                guard ref.sheet == nil || ref.sheet!.lowercased() == sheetName else { return ref }
                return Self._adjust(ref, axis, index: index, delta: delta)
            })
            return text.map { (e.name, $0) }
        }
        // The x14 copies' ranges, and manual page breaks.
        ws.keptElements = ws.keptElements.compactMap { e in
            switch e.name {
            case "extLst":
                return (e.name, KeptRefs.shiftExtRanges(e.text, range: { r in
                    guard let (lo, hi) = axis == .rows ? self._adjustSpan(r.top, r.bottom, index: index, delta: delta)
                                                       : self._adjustSpan(r.left, r.right, index: index, delta: delta) else { return nil }
                    return axis == .rows ? CellRange(top: lo, left: r.left, bottom: hi, right: r.right)
                                         : CellRange(top: r.top, left: lo, bottom: r.bottom, right: hi)
                }))
            case "rowBreaks" where axis == .rows, "colBreaks" where axis == .cols:
                return KeptRefs.shiftBreaks(e.text, moved: { n in
                    // A break before row n (1-based n+1): it moves with that row.
                    if delta > 0 { return n >= index ? n + delta : n }
                    if n < index { return n }
                    if n < deleteEnd { return nil }
                    return n + delta
                }).map { (e.name, $0) }
            default:
                return e
            }
        }
        // Formulas everywhere that point at this sheet.
        let name = ws.name.lowercased()
        _rewriteFormulas { ref, home in
            let onThis = ref.sheet.map { $0.lowercased() == name } ?? (home == si)
            guard onThis else { return ref }
            return Self._adjust(ref, axis, index: index, delta: delta)
        }
        // The selection stays on the same cells where it can.
        let a = active
        let i = axis == .rows ? a.row : a.col
        let j = moved(i) ?? index
        select(axis == .rows ? CellAddress(row: j, col: a.col) : CellAddress(row: a.row, col: j))
    }

    /// A span lo...hi after inserting (delta > 0) before `index` or deleting
    /// `-delta` starting at `index`; nil when deleted entirely.
    func _adjustSpan(_ lo: Int, _ hi: Int, index: Int, delta: Int) -> (Int, Int)? {
        if delta > 0 {
            return (lo >= index ? lo + delta : lo, hi >= index ? hi + delta : hi)
        }
        let end = index - delta   // exclusive
        if lo >= index && hi < end { return nil }
        let a = lo < index ? lo : (lo < end ? index : lo + delta)
        let b = hi < index ? hi : (hi < end ? index - 1 : hi + delta)
        return a <= b ? (a, b) : nil
    }

    /// One reference after a row/column insert or delete on its sheet.
    static func _adjust(_ ref: FormulaRef, _ axis: Axis, index: Int, delta: Int) -> FormulaRef? {
        func get(_ e: RefEnd) -> Int? { axis == .rows ? e.row : e.col }
        func set(_ e: inout RefEnd, _ v: Int) { if axis == .rows { e.row = v } else { e.col = v } }
        var r = ref
        guard let s = get(r.start) else { return r }          // a whole column (rows) is unaffected
        let e0 = r.end.flatMap(get) ?? s
        let lo = min(s, e0), hi = max(s, e0)
        let end = index - delta
        if delta < 0 && r.end == nil {
            // A single cell: gone if deleted, else moved.
            if s >= index && s < end { return nil }
            set(&r.start, s >= end ? s + delta : s)
            return r
        }
        if delta > 0 && r.end == nil {
            set(&r.start, s >= index ? s + delta : s)
            return r
        }
        // A range: inserting inside it grows it; deleting shrinks it.
        let newLo: Int, newHi: Int
        if delta > 0 {
            newLo = lo >= index ? lo + delta : lo
            newHi = hi >= index ? hi + delta : hi
        } else {
            if lo >= index && hi < end { return nil }
            newLo = lo < index ? lo : (lo < end ? index : lo + delta)
            newHi = hi < index ? hi : (hi < end ? index - 1 : hi + delta)
        }
        // Keep which end was written first.
        if s <= e0 { set(&r.start, newLo); if r.end != nil { set(&r.end!, newHi) } }
        else { set(&r.start, newHi); if r.end != nil { set(&r.end!, newLo) } }
        return r
    }

    // MARK: Fill

    /// Ctrl+Enter: what was typed goes into every cell of the selection,
    /// a formula shifted relative to the active cell as Excel does.
    func fillSelection(with text: String) {
        let r = selection
        var items: [(CellAddress, String)] = []
        let expr = text.hasPrefix("=") ? try? Formula.parse(text) : nil
        for row in r.top ... min(r.bottom, r.top + 9999) {
            for col in r.left ... min(r.right, r.left + 999) {
                let a = CellAddress(row: row, col: col)
                if let expr {
                    items.append((a, Formula.text(Formula.shifted(expr, rows: row - active.row, cols: col - active.col))))
                } else {
                    items.append((a, text))
                }
            }
        }
        setInputs(items)
    }

    /// Ctrl+D / Ctrl+R: the first row (column) of the selection copied
    /// into the rest, formulas shifted and formats with them.
    func fillDown() {
        let r = selection
        guard r.rows > 1 else { _fillFrom(CellRange(top: max(0, r.top - 1), left: r.left, bottom: max(0, r.top - 1), right: r.right), into: r); return }
        _fillFrom(CellRange(top: r.top, left: r.left, bottom: r.top, right: r.right), into: r)
    }

    func fillRight() {
        let r = selection
        guard r.cols > 1 else { _fillFrom(CellRange(top: r.top, left: max(0, r.left - 1), bottom: r.bottom, right: max(0, r.left - 1)), into: r); return }
        _fillFrom(CellRange(top: r.top, left: r.left, bottom: r.bottom, right: r.left), into: r)
    }

    private func _fillFrom(_ src: CellRange, into dst: CellRange) {
        var before: [CellAddress: Cell?] = [:]
        let ws = sheet
        for row in dst.top ... dst.bottom {
            for col in dst.left ... dst.right {
                let a = CellAddress(row: row, col: col)
                if src.contains(a) { continue }
                let from = CellAddress(row: src.rows == 1 ? src.top : row, col: src.cols == 1 ? src.left : col)
                before[a] = .some(ws.cells[a])
                ws.cells[a] = _copied(ws.cells[from], from: from, to: a)
            }
        }
        _record(sheet: activeSheet, before: before)
    }

    /// A cell as it reads copied to `to`: formula shifted, all else as is.
    func _copied(_ c: Cell?, from: CellAddress, to: CellAddress) -> Cell? {
        guard var c else { return nil }
        if c.formula == nil, c.rawFormula != nil, from != to {
            // A formula this engine cannot read cannot be re-addressed:
            // the copy carries its value.
            c.rawFormula = nil
            c.input = NumberFormat.display(c.value, "General", width: 255).text
            if case .text(let t) = c.value { c.input = t }
            c.cached = nil
        }
        if let f = c.formula {
            let g = Formula.shifted(f, rows: to.row - from.row, cols: to.col - from.col)
            c.formula = g
            c.input = Formula.text(g)
            c.cached = nil
        }
        return c
    }

    /// The fill handle dragged from the selection to `target`: a series
    /// where the selection holds one (1, 2 → 3, 4; Jan → Feb; Item 1 →
    /// Item 2; dates by day), copies otherwise, formulas shifted.
    func fillSeries(to target: CellRange) {
        if refusesEdit(target.cells) { return }
        let src = selection
        guard target != src, target.top == src.top || target.left == src.left || target.bottom == src.bottom || target.right == src.right
        else { return }
        let vertical = target.rows != src.rows
        let ws = sheet
        var before: [CellAddress: Cell?] = [:]
        let lines = vertical ? (src.left ... src.right).map { $0 } : (src.top ... src.bottom).map { $0 }
        for line in lines {
            // The seed cells along the fill direction.
            let seed: [CellAddress] = vertical
                ? (src.top ... src.bottom).map { CellAddress(row: $0, col: line) }
                : (src.left ... src.right).map { CellAddress(row: line, col: $0) }
            let forward = vertical ? target.bottom > src.bottom : target.right > src.right
            let span: [CellAddress] = vertical
                ? (forward ? Array(src.bottom + 1 ... target.bottom) : Array((target.top ..< src.top).reversed())).map { CellAddress(row: $0, col: line) }
                : (forward ? Array(src.right + 1 ... target.right) : Array((target.left ..< src.left).reversed())).map { CellAddress(row: line, col: $0) }
            let series = _series(seed.map { ws.cells[$0] }, count: span.count, forward: forward)
            for (k, a) in span.enumerated() {
                before[a] = .some(ws.cells[a])
                if let v = series?[k] {
                    var c = ws.cells[seed[forward ? seed.count - 1 : 0]] ?? Cell(input: "")
                    c.formula = nil; c.cached = nil
                    c.input = v
                    if let parsed = InputParser.parse(v) { c.value = parsed.value } else { c.value = .text(v) }
                    ws.cells[a] = c
                } else {
                    // Copies cycle through the seed.
                    let from = seed[(forward ? k : seed.count - 1 - (k % seed.count)) % seed.count]
                    ws.cells[a] = _copied(ws.cells[from], from: from, to: a)
                }
            }
        }
        _record(sheet: activeSheet, before: before)
        select(range: CellRange(src.topLeft, src.bottomRight).union(target), active: active)
    }

    private static let _months = ["January", "February", "March", "April", "May", "June", "July", "August",
                                  "September", "October", "November", "December"]
    private static let _days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// The inputs a series continues with, or nil to copy the seed instead.
    func _series(_ seed: [Cell?], count: Int, forward: Bool) -> [String]? {
        guard let first = seed.first, let c0 = first, c0.formula == nil else { return nil }
        // Numbers (and dates, which are numbers): the seed's last step, 1 day
        // for a single date, none (a copy) for a single plain number.
        let numbers = seed.compactMap { $0?.value.number }
        if numbers.count == seed.count {
            let isDate = book.style(c0.style).numberFormat.lowercased().contains("d")
            let step: Double
            if numbers.count >= 2 { step = numbers[numbers.count - 1] - numbers[numbers.count - 2] }
            else if isDate { step = 1 }
            else { return nil }
            return (0 ..< count).map { k in
                NumberFormat.full(forward ? numbers.last! + step * Double(k + 1) : numbers.first! - step * Double(k + 1))
            }
        }
        // Month and day names.
        if case .text(let t) = c0.value {
            for list in [Self._months, Self._days] {
                let short = list.map { String($0.prefix(3)) }
                if let i = list.firstIndex(where: { $0.lowercased() == t.lowercased() }) ?? short.firstIndex(where: { $0.lowercased() == t.lowercased() }) {
                    let useShort = t.count == 3
                    return (1 ... max(1, count)).prefix(count).map { k in
                        let j = ((i + (forward ? k : -k)) % list.count + list.count) % list.count
                        let name = useShort ? short[j] : list[j]
                        return t == t.uppercased() ? name.uppercased() : name
                    }
                }
            }
            // Text ending in a number: Item 1 → Item 2.
            let digits = t.reversed().prefix { $0.isNumber }
            if !digits.isEmpty, digits.count < t.count, let n = Int(String(digits.reversed())) {
                let stem = String(t.dropLast(digits.count))
                return (1 ... max(1, count)).prefix(count).map { k in stem + String(n + (forward ? k : -k)) }
            }
        }
        return nil
    }

    // MARK: Copy, paste, move

    /// What ⌘C/⌘X put on the app's own clipboard: the cells with their
    /// formulas and formats, so a paste here is exact. Other apps get the
    /// tab-separated text (the grid writes that to the system clipboard).
    struct Clip {
        let sheet: Int
        let range: CellRange
        let cells: [CellAddress: Cell]   // relative to range.topLeft
        let cut: Bool
        let text: String                 // what was put on the system clipboard
    }

    func clip(cut: Bool, text: String) -> Clip {
        let r = selection
        var cells: [CellAddress: Cell] = [:]
        for (a, c) in sheet.cells where r.contains(a) {
            cells[CellAddress(row: a.row - r.top, col: a.col - r.left)] = c
        }
        return Clip(sheet: activeSheet, range: r, cells: cells, cut: cut, text: text)
    }

    /// Paste a clip at the selection's top-left. A copy shifts formulas by
    /// the distance; a cut moves the cells and points every formula that
    /// referred to them at their new place, as Excel's cut does.
    func paste(_ clip: Clip) {
        let at = selection.topLeft
        if refusesEdit(CellRange(top: at.row, left: at.col, bottom: min(CellAddress.maxRows - 1, at.row + clip.range.rows - 1),
                                 right: min(CellAddress.maxCols - 1, at.col + clip.range.cols - 1)).cells) { return }
        let origin = selection.topLeft
        let dst = CellRange(top: origin.row, left: origin.col,
                            bottom: origin.row + clip.range.rows - 1, right: origin.col + clip.range.cols - 1)
        guard dst.bottom < CellAddress.maxRows, dst.right < CellAddress.maxCols else { return }
        if clip.cut {
            structural { _move(clip, to: origin) }
        } else {
            let ws = sheet
            var before: [CellAddress: Cell?] = [:]
            for row in dst.top ... dst.bottom {
                for col in dst.left ... dst.right {
                    let a = CellAddress(row: row, col: col)
                    let rel = CellAddress(row: row - dst.top, col: col - dst.left)
                    before[a] = .some(ws.cells[a])
                    ws.cells[a] = _copied(clip.cells[rel], from: CellAddress(row: clip.range.top + rel.row, col: clip.range.left + rel.col), to: a)
                }
            }
            _record(sheet: activeSheet, before: before)
        }
        select(range: dst, active: origin)
    }

    private func _move(_ clip: Clip, to origin: CellAddress) {
        guard clip.sheet < book.sheets.count else { return }
        let src = book.sheets[clip.sheet]
        let dstSheet = sheet
        let dr = origin.row - clip.range.top, dc = origin.col - clip.range.left
        // Clear the source, then write the destination.
        for a in Array(src.cells.keys) where clip.range.contains(a) { src.cells[a] = nil }
        let dst = CellRange(top: origin.row, left: origin.col, bottom: origin.row + clip.range.rows - 1, right: origin.col + clip.range.cols - 1)
        for a in Array(dstSheet.cells.keys) where dst.contains(a) { dstSheet.cells[a] = nil }
        for (rel, c) in clip.cells {
            dstSheet.cells[CellAddress(row: dst.top + rel.row, col: dst.left + rel.col)] = c
        }
        // References into the moved block follow it.
        let srcName = src.name
        let sameSheet = clip.sheet == activeSheet
        _rewriteFormulas { ref, home in
            let onSource = ref.sheet.map { $0.lowercased() == srcName.lowercased() } ?? (home == clip.sheet)
            guard onSource, ref.isCell, let r = ref.start.row, let c = ref.start.col,
                  clip.range.contains(CellAddress(row: r, col: c)) else {
                // A range wholly inside the block moves too.
                if onSource, !ref.isCell, ref.start.row != nil, ref.start.col != nil, clip.range.contains(ref.range.topLeft),
                   clip.range.contains(ref.range.bottomRight) {
                    var out = ref
                    out.start.row! += dr; out.start.col! += dc
                    out.end?.row? += dr; out.end?.col? += dc
                    if !sameSheet, home != activeSheet { out.sheet = dstSheet.name }
                    return out
                }
                return ref
            }
            var out = ref
            out.start.row = r + dr
            out.start.col = c + dc
            if !sameSheet {
                if home == activeSheet { out.sheet = nil } else { out.sheet = dstSheet.name }
            }
            return out
        }
    }
}

extension CellRange {
    func union(_ o: CellRange) -> CellRange {
        CellRange(top: Swift.min(top, o.top), left: Swift.min(left, o.left), bottom: Swift.max(bottom, o.bottom), right: Swift.max(right, o.right))
    }
}

// MARK: - Find and replace

extension WorkbookController {
    /// What a cell is searched as: its formula text for a formula (Excel's
    /// "Look in: Formulas"), else what it shows.
    func _searchText(_ c: Cell, _ a: CellAddress, sheet ws: Worksheet) -> String {
        if let f = c.formula { return Formula.text(f) }
        return NumberFormat.display(c.value, book.style(c.style).numberFormat, width: 255).text
    }

    /// The next cell after the active one (row by row, then the following
    /// sheets) whose text contains `query`, case-insensitively; selects it.
    @discardableResult
    func findNext(_ query: String, backwards: Bool = false) -> Bool {
        guard !query.isEmpty else { return false }
        let q = query.lowercased()
        let n = book.sheets.count
        for step in 0 ... n {
            let si = ((activeSheet + (backwards ? -step : step)) % n + n) % n
            let ws = book.sheets[si]
            var hits = ws.cells.filter { _searchText($0.value, $0.key, sheet: ws).lowercased().containsSubstring(q) }.map(\.key).sorted()
            if backwards { hits.reverse() }
            let here = active
            let next: CellAddress?
            if step == 0 {
                next = hits.first { backwards ? $0 < here : $0 > here }
            } else if step == n {
                next = hits.first   // wrapped back round to where we started
            } else {
                next = hits.first
            }
            if let a = next {
                if si != activeSheet { activeSheet = si }
                select(a)
                return true
            }
        }
        return false
    }

    /// Replace in the active cell if it matches, then move to the next match.
    @discardableResult
    func replaceCurrent(_ query: String, with replacement: String) -> Bool {
        let q = query.lowercased()
        if let c = sheet.cells[active], _searchText(c, active, sheet: sheet).lowercased().containsSubstring(q) {
            setInput(_replacing(input(active), query, replacement), at: active)
        }
        return findNext(query)
    }

    /// Every match on every sheet, as one undo step. Returns the count.
    @discardableResult
    func replaceAll(_ query: String, with replacement: String) -> Int {
        guard !query.isEmpty else { return 0 }
        let q = query.lowercased()
        var count = 0
        structural {
            for ws in book.sheets {
                for (a, c) in ws.cells where _searchText(c, a, sheet: ws).lowercased().containsSubstring(q) {
                    let text = c.formula.map(Formula.text) ?? c.input
                    let new = _replacing(text, query, replacement)
                    guard new != text else { continue }
                    count += 1
                    var cell = c
                    cell.input = new
                    cell.rawFormula = nil
                    if new.hasPrefix("="), let f = try? Formula.parse(new) {
                        cell.formula = f; cell.value = .empty
                    } else if let parsed = InputParser.parse(new) {
                        cell.formula = nil; cell.value = parsed.value
                    } else {
                        cell.formula = nil; cell.value = .text(new)
                    }
                    ws.cells[a] = cell
                }
            }
        }
        return count
    }

    /// Case-insensitive replace of every occurrence.
    func _replacing(_ s: String, _ query: String, _ replacement: String) -> String {
        var out = ""
        var from = s.startIndex
        while let r = s.findRange(of: query, caseSensitive: false, in: from ..< s.endIndex) {
            out += s[from ..< r.lowerBound]
            out += replacement
            from = r.upperBound
        }
        return out + s[from...]
    }
}
