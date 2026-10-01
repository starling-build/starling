// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Outlines (grouping), as Excel keeps them, for rows and for columns: an
// index's level is its `outlineLevel` (a `<row>`'s, or a `<col>` run's), a
// group is a run at that level or deeper, its summary row (column) sits
// after the run — before it when sheetPr's outlinePr says
// summaryBelow="0" (summaryRight="0") — and carries `collapsed="1"`
// while the group is closed, the group's rows then hidden. Group/Ungroup
// change levels; the outline gutters' +/− and level buttons open and
// close groups. Undoable. Hide/Unhide live here too: they are the same
// hidden sets.

import Foundation

struct OutlineGroup: Equatable {
    var level: Int
    /// The rows (columns) in the group, not counting its summary.
    var span: ClosedRange<Int>
    var summary: Int
}

extension Worksheet {
    /// Levels by index, for the indices that have one.
    func outlineLevels(_ axis: WorkbookController.Axis) -> [Int: Int] {
        var out: [Int: Int] = [:]
        switch axis {
        case .rows:
            for (r, a) in rowAttrs { if let l = a["outlineLevel"].flatMap({ Int($0) }), l > 0 { out[r] = l } }
        case .cols:
            for run in colAttrRuns {
                guard let v = run.attrs["outlineLevel"], let l = Int(v) else { continue }
                for c in run.lo ... min(run.hi, run.lo + 4096) { if l > 0 { out[c] = l } else { out[c] = nil } }
            }
        }
        return out
    }

    func outlineLevel(_ axis: WorkbookController.Axis, _ i: Int) -> Int {
        axis == .rows ? outlineLevel(row: i) : (outlineAttr(.cols, i, "outlineLevel").flatMap { Int($0) } ?? 0)
    }

    func maxOutlineLevel(_ axis: WorkbookController.Axis) -> Int { outlineLevels(axis).values.max() ?? 0 }

    func outlineAttr(_ axis: WorkbookController.Axis, _ i: Int, _ name: String) -> String? {
        switch axis {
        case .rows: return rowAttrs[i]?[name]
        case .cols: return colAttrRuns.last { $0.lo <= i && i <= $0.hi && $0.attrs[name] != nil }?.attrs[name]
        }
    }

    /// Set (nil: remove) one attribute of one row or column; a column's run
    /// is split around it.
    func setOutlineAttr(_ axis: WorkbookController.Axis, _ i: Int, _ name: String, _ value: String?) {
        switch axis {
        case .rows:
            rowAttrs[i, default: [:]][name] = value
            if rowAttrs[i]?.isEmpty == true { rowAttrs[i] = nil }
        case .cols:
            guard outlineAttr(.cols, i, name) != value else { return }
            var runs: [(lo: Int, hi: Int, attrs: [String: String])] = []
            var touched = false
            for r in colAttrRuns {
                guard r.lo <= i && i <= r.hi else { runs.append(r); continue }
                if r.lo < i { runs.append((r.lo, i - 1, r.attrs)) }
                var mid = r.attrs
                mid[name] = value
                if !mid.isEmpty { runs.append((i, i, mid)) }
                touched = true
                if i < r.hi { runs.append((i + 1, r.hi, r.attrs)) }
            }
            if !touched, let value { runs.append((i, i, [name: value])) }
            colAttrRuns = runs
        }
    }

    func summaryAfter(_ axis: WorkbookController.Axis) -> Bool {
        let key = axis == .rows ? "summaryBelow=\"0\"" : "summaryRight=\"0\""
        return !(keptElements.first { $0.name == "sheetPr" }?.text.containsSubstring(key) ?? false)
    }

    func hidden(_ axis: WorkbookController.Axis) -> Set<Int> { axis == .rows ? hiddenRows : hiddenCols }

    func setHidden(_ axis: WorkbookController.Axis, _ i: Int, _ on: Bool) {
        switch (axis, on) {
        case (.rows, true): hiddenRows.insert(i)
        case (.rows, false): hiddenRows.remove(i)
        case (.cols, true): hiddenCols.insert(i)
        case (.cols, false): hiddenCols.remove(i)
        }
    }

    /// Every group, outermost first.
    func outlineGroups(_ axis: WorkbookController.Axis) -> [OutlineGroup] {
        let levels = outlineLevels(axis)
        guard !levels.isEmpty else { return [] }
        let indices = levels.keys.sorted()
        let after = summaryAfter(axis)
        var out: [OutlineGroup] = []
        for level in 1 ... (levels.values.max() ?? 0) {
            var start: Int? = nil, last = -2
            func close() {
                if let s = start { out.append(OutlineGroup(level: level, span: s ... last, summary: after ? last + 1 : max(0, s - 1))) }
                start = nil
            }
            for i in indices where levels[i]! >= level {
                if i != last + 1 { close(); start = i }
                last = i
            }
            close()
        }
        return out
    }

    func isCollapsed(_ g: OutlineGroup, _ axis: WorkbookController.Axis) -> Bool {
        if outlineAttr(axis, g.summary, "collapsed") == "1" { return true }
        let h = hidden(axis)
        return g.span.allSatisfy { h.contains($0) }
    }

    var maxOutlineLevel: Int { maxOutlineLevel(.rows) }
    func rowGroups() -> [OutlineGroup] { outlineGroups(.rows) }
}

extension WorkbookController {
    /// Data → Group / Ungroup: whole selected columns go a level deeper
    /// (shallower); anything else, its rows.
    func group(_ deeper: Bool) {
        let wholeCols = selection.top == 0 && selection.bottom == CellAddress.maxRows - 1 && selection.cols < CellAddress.maxCols
        group(wholeCols ? .cols : .rows, deeper)
    }

    func group(_ axis: Axis, _ deeper: Bool) {
        if refuses(axis == .rows ? "formatRows" : "formatColumns") { return }
        let ws = sheet
        let r = selection
        let span = axis == .rows ? r.top ... r.bottom : r.left ... r.right
        guard span.count < (axis == .rows ? CellAddress.maxRows : CellAddress.maxCols) else { return }
        structural {
            for i in span {
                let next = max(0, min(7, ws.outlineLevel(axis, i) + (deeper ? 1 : -1)))
                ws.setOutlineAttr(axis, i, "outlineLevel", next == 0 ? nil : "\(next)")
                if next == 0 { ws.setHidden(axis, i, false) }
            }
            _syncOutlineLevel(ws, axis)
        }
    }

    private func _syncOutlineLevel(_ ws: Worksheet, _ axis: Axis) {
        let m = ws.maxOutlineLevel(axis)
        ws.formatPrAttrs[axis == .rows ? "outlineLevelRow" : "outlineLevelCol"] = m > 0 ? "\(m)" : nil
    }

    /// The gutter's +/−: close an open group, open a closed one (nested
    /// groups that were closed stay closed).
    func toggleGroup(_ g: OutlineGroup, _ axis: Axis = .rows) {
        let ws = sheet
        let closing = !ws.isCollapsed(g, axis)
        structural {
            if closing {
                for i in g.span { ws.setHidden(axis, i, true) }
                ws.setOutlineAttr(axis, g.summary, "collapsed", "1")
            } else {
                ws.setOutlineAttr(axis, g.summary, "collapsed", nil)
                _show(g, axis, ws, ws.outlineGroups(axis))
            }
        }
        _leaveHidden(axis, to: g.summary)
    }

    private func _show(_ g: OutlineGroup, _ axis: Axis, _ ws: Worksheet, _ all: [OutlineGroup]) {
        let inner = all.filter { $0.level == g.level + 1 && g.span.contains($0.span.lowerBound) }
        for i in g.span {
            if let sub = inner.first(where: { $0.span.contains(i) }) {
                if i == sub.span.lowerBound, ws.outlineAttr(axis, sub.summary, "collapsed") != "1" { _show(sub, axis, ws, all) }
            } else {
                ws.setHidden(axis, i, false)
            }
        }
    }

    /// The gutter's level button `k`: groups at level k or deeper closed,
    /// shallower ones open — Excel's 1 shows only the top level.
    func showOutlineLevel(_ k: Int, _ axis: Axis = .rows) {
        let ws = sheet
        structural {
            for (i, level) in ws.outlineLevels(axis) { ws.setHidden(axis, i, level >= k) }
            for g in ws.outlineGroups(axis) where g.level <= k {
                ws.setOutlineAttr(axis, g.summary, "collapsed", g.level == k ? "1" : nil)
            }
        }
        _leaveHidden(axis, to: 0)
    }

    /// When the active cell was just hidden, move it out to `index`.
    private func _leaveHidden(_ axis: Axis, to index: Int) {
        let ws = sheet
        if axis == .rows, ws.isRowHidden(active.row), selection.rows == 1 { select(CellAddress(row: index, col: active.col)) }
        if axis == .cols, ws.isColHidden(active.col), selection.cols == 1 { select(CellAddress(row: active.row, col: index)) }
    }

    /// Hide (or show) the selected rows or columns. Showing takes in the
    /// hidden ones inside the selection — select either side of them, as in
    /// Excel — and gives each its own size back; a 0-wide one from a file
    /// gets the default.
    func setHidden(_ axis: Axis, _ hide: Bool) {
        if refuses(axis == .rows ? "formatRows" : "formatColumns") { return }
        let ws = sheet
        let r = selection
        // Hiding every row (column) is refused, as in Excel.
        if hide, axis == .rows ? r.rows == CellAddress.maxRows : r.cols == CellAddress.maxCols { return }
        structural {
            if axis == .rows {
                let span = r.top ... r.bottom
                if hide {
                    ws.hiddenRows.formUnion(span)
                } else {
                    ws.hiddenRows = ws.hiddenRows.filter { !span.contains($0) }
                    for k in Array(ws.rowHeights.keys) where span.contains(k) && ws.rowHeights[k] == 0 { ws.rowHeights[k] = nil }
                }
            } else {
                let span = r.left ... r.right
                if hide {
                    ws.hiddenCols.formUnion(span)
                } else {
                    ws.hiddenCols = ws.hiddenCols.filter { !span.contains($0) }
                    for k in Array(ws.colWidths.keys) where span.contains(k) && ws.colWidths[k] == 0 {
                        ws.colWidths[k] = nil
                        ws.colWidthChars[k] = nil
                    }
                }
            }
        }
    }
}
