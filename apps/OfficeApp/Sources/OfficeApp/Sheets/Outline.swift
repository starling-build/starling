// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Row outlines (grouping), as Excel keeps them: a row's level is its
// `outlineLevel`, a group is a run of rows at that level or deeper, its
// summary row sits below the run (above, when sheetPr's outlinePr says
// summaryBelow="0") and carries `collapsed="1"` while the group is closed,
// the group's rows then hidden. Group/Ungroup change levels; the outline
// gutter's +/− and level buttons open and close groups. Undoable.

import Foundation

struct RowGroup: Equatable {
    var level: Int
    var rows: ClosedRange<Int>
    var summary: Int
}

extension Worksheet {
    var maxOutlineLevel: Int { rowAttrs.values.compactMap { $0["outlineLevel"].flatMap { Int($0) } }.max() ?? 0 }

    var summaryBelow: Bool {
        !(keptElements.first { $0.name == "sheetPr" }?.text.containsSubstring("summaryBelow=\"0\"") ?? false)
    }

    /// Every group, outermost first.
    func rowGroups() -> [RowGroup] {
        let leveled = rowAttrs.compactMap { (r, a) in a["outlineLevel"].flatMap { Int($0) }.map { (r, $0) } }.filter { $0.1 > 0 }
        guard !leveled.isEmpty else { return [] }
        let levels = Dictionary(uniqueKeysWithValues: leveled)
        let rows = levels.keys.sorted()
        let below = summaryBelow
        var out: [RowGroup] = []
        for level in 1 ... (levels.values.max() ?? 0) {
            var start: Int? = nil, last = -2
            func close() {
                if let s = start { out.append(RowGroup(level: level, rows: s ... last, summary: below ? last + 1 : max(0, s - 1))) }
                start = nil
            }
            for r in rows where levels[r]! >= level {
                if r != last + 1 { close(); start = r }
                if start == nil { start = r }
                last = r
            }
            close()
        }
        return out
    }

    func isCollapsed(_ g: RowGroup) -> Bool { rowAttrs[g.summary]?["collapsed"] == "1" || g.rows.allSatisfy { hiddenRows.contains($0) } }
}

extension WorkbookController {
    /// Data → Group / Ungroup: the selected rows one level deeper or shallower.
    func groupRows(_ deeper: Bool) {
        if refuses("formatRows") { return }
        let ws = sheet
        let r = selection
        guard r.rows < CellAddress.maxRows else { return }
        structural {
            for row in r.top ... r.bottom {
                let level = ws.outlineLevel(row: row)
                let next = max(0, min(7, level + (deeper ? 1 : -1)))
                if next == 0 {
                    ws.rowAttrs[row]?["outlineLevel"] = nil
                    if ws.rowAttrs[row]?.isEmpty == true { ws.rowAttrs[row] = nil }
                } else {
                    ws.rowAttrs[row, default: [:]]["outlineLevel"] = "\(next)"
                }
                if !deeper && next == 0 { ws.hiddenRows.remove(row) }
            }
            _syncOutlineLevel(ws)
        }
    }

    private func _syncOutlineLevel(_ ws: Worksheet) {
        let m = ws.maxOutlineLevel
        if m > 0 { ws.formatPrAttrs["outlineLevelRow"] = "\(m)" } else { ws.formatPrAttrs["outlineLevelRow"] = nil }
    }

    /// The gutter's +/−: close an open group, open a closed one (nested
    /// groups that were closed stay closed).
    func toggleGroup(_ g: RowGroup) {
        let ws = sheet
        let closing = !ws.isCollapsed(g)
        structural {
            if closing {
                for r in g.rows { ws.hiddenRows.insert(r) }
                ws.rowAttrs[g.summary, default: [:]]["collapsed"] = "1"
            } else {
                ws.rowAttrs[g.summary]?["collapsed"] = nil
                if ws.rowAttrs[g.summary]?.isEmpty == true { ws.rowAttrs[g.summary] = nil }
                _show(g, ws)
            }
        }
        if selection.rows == 1, ws.isRowHidden(active.row) { select(CellAddress(row: g.summary, col: active.col)) }
    }

    private func _show(_ g: RowGroup, _ ws: Worksheet) {
        let inner = ws.rowGroups().filter { $0.level == g.level + 1 && g.rows.contains($0.rows.lowerBound) }
        for r in g.rows {
            if let sub = inner.first(where: { $0.rows.contains(r) }) {
                if r == sub.rows.lowerBound, !(ws.rowAttrs[sub.summary]?["collapsed"] == "1") { _show(sub, ws) }
            } else {
                ws.hiddenRows.remove(r)
            }
        }
    }

    /// The gutter's level button `k`: rows at level k or deeper closed,
    /// shallower ones open — Excel's 1 shows only the top level.
    func showOutlineLevel(_ k: Int) {
        let ws = sheet
        structural {
            for r in Array(ws.rowAttrs.keys) {
                let level = ws.outlineLevel(row: r)
                guard level > 0 else { continue }
                if level >= k { ws.hiddenRows.insert(r) } else { ws.hiddenRows.remove(r) }
            }
            for g in ws.rowGroups() {
                if g.level == k { ws.rowAttrs[g.summary, default: [:]]["collapsed"] = "1" }
                else if g.level < k {
                    ws.rowAttrs[g.summary]?["collapsed"] = nil
                    if ws.rowAttrs[g.summary]?.isEmpty == true { ws.rowAttrs[g.summary] = nil }
                }
            }
        }
        if ws.isRowHidden(active.row) { select(CellAddress(row: 0, col: active.col)) }
    }
}
