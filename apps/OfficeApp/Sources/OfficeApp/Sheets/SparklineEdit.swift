// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Sparklines in the workbook: reading them for painting, and Insert >
// Sparklines (add a group over a data range and a location range, change a
// group's look, clear them).

import Foundation
import OfficeText

/// What one cell's sparkline draws: the numbers, the vertical range and the
/// group's colours, already resolved.
struct SparkLook {
    var group: SparklineGroup
    var values: [Double?]
    var lo: Double
    var hi: Double
    var colors: [String: UInt32]
}

enum SparklineProblem: Equatable {
    case badData, badLocation, mismatch

    var message: String {
        switch self {
        case .badData: return "The data range isn't valid."
        case .badLocation: return "The location range isn't valid."
        case .mismatch: return "The location range doesn't match the data range: it needs one cell for each row (or column) of data."
        }
    }
}

extension WorkbookController {
    func sparklineGroups() -> [SparklineGroup] {
        let text = sheet.keptElements.first { $0.name == "extLst" }?.text
        if let c = SparklineCache.last, c.text == text { return c.groups }
        let g = Sparklines.groups(inExtLst: text)
        SparklineCache.last = (text, g)
        return g
    }

    /// Replace the sheet's sparkline groups (one undo step).
    func setSparklineGroups(_ groups: [SparklineGroup]) {
        let ws = sheet
        structural {
            let i = ws.keptElements.firstIndex { $0.name == "extLst" }
            let text = Sparklines.extLst(replacing: i.map { ws.keptElements[$0].text }, with: groups.filter { !$0.items.isEmpty })
            if let text { if let i { ws.keptElements[i].text = text } else { ws.keptElements.append(("extLst", text)) } }
            else if let i { ws.keptElements.remove(at: i) }
        }
    }

    /// The group and item that show in `cell`, if any.
    func sparklineAt(_ cell: CellAddress) -> (group: Int, item: Int)? {
        for (gi, g) in sparklineGroups().enumerated() { if let ii = g.items.firstIndex(where: { $0.cell == cell }) { return (gi, ii) } }
        return nil
    }

    /// Resolve a data reference (`Sheet1!A1:E1`, `'My Sheet'!A1:E1` or `A1:E1`) to a sheet and range.
    private func _sparkRange(_ f: String) -> (Int, CellRange)? {
        var name: String? = nil
        var ref = f
        if let bang = f.lastIndex(of: "!") {
            var n = String(f[f.startIndex ..< bang])
            if n.hasPrefix("'"), n.hasSuffix("'"), n.count >= 2 { n = String(n.dropFirst().dropLast()).replacingAll("''", with: "'") }
            name = n
            ref = String(f[f.index(after: bang)...])
        }
        let si = name.flatMap { n in book.sheets.firstIndex { $0.name.lowercased() == n.lowercased() } } ?? (name == nil ? activeSheet : nil)
        guard let si, let r = CellRange(ref) else { return nil }
        return (si, r)
    }

    private func _sparkNumbers(_ f: String) -> [Double?] {
        guard let (si, r) = _sparkRange(f) else { return [] }
        return engine.rangeValues(si, r).map { $0.number }
    }

    func sparklineLook(_ cell: CellAddress) -> SparkLook? {
        guard let (gi, ii) = sparklineAt(cell) else { return nil }
        let g = sparklineGroups()[gi]
        let values = _sparkNumbers(g.items[ii].f)
        func range(_ v: [Double?]) -> (Double, Double)? {
            let n = v.compactMap { $0 }
            guard let lo = n.min(), let hi = n.max() else { return nil }
            return (lo, hi)
        }
        let own = range(values) ?? (0, 0)
        let all = g.minType == "group" || g.maxType == "group" ? range(g.items.flatMap { _sparkNumbers($0.f) }) ?? own : own
        var lo = g.minType == "group" ? all.0 : own.0, hi = g.maxType == "group" ? all.1 : own.1
        if g.minType == "custom", let m = g.manualMin { lo = m }
        if g.maxType == "custom", let m = g.manualMax { hi = m }
        var colors: [String: UInt32] = [:]
        for name in Sparklines.colorOrder {
            let a = g.color(name) ?? Sparklines.defaultColor(name)
            colors[name] = Xlsx._color(XNode(name: name, attrs: a), theme: book.themeColors) ?? 0x376092
        }
        return SparkLook(group: g, values: values, lo: lo, hi: hi, colors: colors)
    }

    /// Insert > Sparklines: one sparkline per row (or column) of `data`, in the cells of `location`.
    @discardableResult
    func addSparklines(kind: SparklineGroup.Kind, data: String, location: String) -> SparklineProblem? {
        guard let (dsi, dr) = _sparkRange(data) else { return .badData }
        guard let lr = CellRange(location.trimmingSparkSpaces.replacingAll("$", with: "")) else { return .badLocation }
        let n = lr.rows * lr.cols
        // One sparkline for each row of data when the location is a column of that many cells,
        // each column when it is a row (the location's own shape decides when both fit).
        let byRows: Bool
        if n == 1 { guard dr.rows == 1 || dr.cols == 1 else { return .mismatch }; byRows = dr.rows == 1 }
        else if lr.cols == 1 { guard dr.rows == n || dr.cols == n else { return .mismatch }; byRows = dr.rows == n }
        else if lr.rows == 1 { guard dr.cols == n || dr.rows == n else { return .mismatch }; byRows = dr.cols != n }
        else { return .mismatch }
        let sheetPart = data.lastIndex(of: "!").map { String(data[data.startIndex ... $0]) } ?? Self._quotedSheet(book.sheets[dsi].name) + "!"
        var cells: [CellAddress] = []
        for row in lr.top ... lr.bottom { for col in lr.left ... lr.right { cells.append(CellAddress(row: row, col: col)) } }
        var g = SparklineGroup.new(kind: kind)
        for (i, cell) in cells.enumerated() {
            let part = byRows ? CellRange(top: dr.top + i, left: dr.left, bottom: dr.top + i, right: dr.right)
                              : CellRange(top: dr.top, left: dr.left + i, bottom: dr.bottom, right: dr.left + i)
            g.items.append((sheetPart + part.a1, cell))
        }
        var groups = sparklineGroups()
        let taken = Set(cells)
        for gi in groups.indices { groups[gi].items.removeAll { taken.contains($0.cell) } }
        groups.append(g)
        setSparklineGroups(groups)
        return nil
    }

    /// Change the look of the group that shows in `cell`.
    func updateSparklineGroup(at cell: CellAddress, _ change: (inout SparklineGroup) -> Void) {
        guard let (gi, _) = sparklineAt(cell) else { return }
        var groups = sparklineGroups()
        change(&groups[gi])
        setSparklineGroups(groups)
    }

    /// Clear the sparklines in `range` (Sparkline > Clear).
    func clearSparklines(in range: CellRange) {
        var groups = sparklineGroups()
        let before = groups.reduce(0) { $0 + $1.items.count }
        for gi in groups.indices { groups[gi].items.removeAll { range.contains($0.cell) } }
        if groups.reduce(0, { $0 + $1.items.count }) != before { setSparklineGroups(groups) }
    }

    private static func _quotedSheet(_ n: String) -> String {
        let plain = !n.isEmpty && n.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } && !(n.first?.isNumber ?? true)
        return plain ? n : "'" + n.replacingAll("'", with: "''") + "'"
    }
}

enum SparklineCache {
    nonisolated(unsafe) static var last: (text: String?, groups: [SparklineGroup])? = nil
}

private extension String {
    var trimmingSparkSpaces: String { String(drop { $0 == " " }.reversed().drop { $0 == " " }.reversed()) }
}
