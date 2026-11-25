// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-6c: Data → Consolidate. Several source ranges (on any sheets) are combined into one block at
// the active cell with one function, matched by position or by the labels in their top row / left
// column. "Create links to source data" keeps live formulas; without it the results are plain values.
// One undo step.

import Foundation

enum ConsolidateFunction: Int, CaseIterable {
    case sum, count, average, max, min, product, countNumbers, stdDev, stdDevP, variance, varianceP
    var label: String {
        switch self {
        case .sum: return "Sum"
        case .count: return "Count"
        case .average: return "Average"
        case .max: return "Max"
        case .min: return "Min"
        case .product: return "Product"
        case .countNumbers: return "Count Numbers"
        case .stdDev: return "StdDev"
        case .stdDevP: return "StdDevp"
        case .variance: return "Var"
        case .varianceP: return "Varp"
        }
    }
    /// The worksheet function the result cells use.
    var formulaName: String {
        switch self {
        case .sum: return "SUM"
        case .count: return "COUNTA"
        case .average: return "AVERAGE"
        case .max: return "MAX"
        case .min: return "MIN"
        case .product: return "PRODUCT"
        case .countNumbers: return "COUNT"
        case .stdDev: return "STDEV"
        case .stdDevP: return "STDEVP"
        case .variance: return "VAR"
        case .varianceP: return "VARP"
        }
    }
}

struct ConsolidateSource: Hashable {
    var sheet: Int
    var range: CellRange
}

enum ConsolidateProblem: Equatable {
    case noSources, badReference(String), overlapsSource, offSheet, nothingToWrite, mergedCells
    var message: String {
        switch self {
        case .noSources: return "Add at least one reference to consolidate."
        case .badReference(let t): return "\"\(t)\" is not a valid reference. Use a range like Sheet2!A1:C10."
        case .overlapsSource: return "The results would land on top of a source range. Pick an empty cell elsewhere first."
        case .offSheet: return "The results would run past the edge of the sheet."
        case .nothingToWrite: return "The references hold nothing to consolidate."
        case .mergedCells: return "The results would land on merged cells. Unmerge them first."
        }
    }
}

extension WorkbookController {
    /// "Sheet2!A1:C10", "'My Sheet'!$A$1:$C$10" or "A1:C10" (the active sheet) → a source, or nil.
    func parseConsolidateReference(_ text: String) -> ConsolidateSource? {
        var t = text.trimmingWhitespace().replacingAll("$", with: "")
        guard !t.isEmpty else { return nil }
        var si = activeSheet
        if let bang = t.lastIndex(of: "!") {
            var name = String(t[t.startIndex ..< bang])
            t = String(t[t.index(after: bang)...])
            if name.hasPrefix("'"), name.hasSuffix("'"), name.count >= 2 {
                name = String(name.dropFirst().dropLast()).replacingAll("''", with: "'")
            }
            guard let i = book.sheets.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) else { return nil }
            si = i
        }
        guard let r = CellRange(t.uppercased()) else { return nil }
        return ConsolidateSource(sheet: si, range: r)
    }

    /// The reference text for a source, as the dialog's list shows it.
    func consolidateReferenceText(_ s: ConsolidateSource) -> String {
        Formula.quoteSheet(book.sheets[s.sheet].name) + "!" + s.range.a1
    }

    /// Combine `sources` into a block whose top-left is `at` on the active sheet. Returns the number
    /// of result cells, or the problem. Matching is by label where `topRow` / `leftColumn` are set,
    /// otherwise by position.
    func consolidate(_ sources: [ConsolidateSource], function: ConsolidateFunction, topRow: Bool, leftColumn: Bool,
                     link: Bool, at dest: CellAddress) -> (cells: Int?, problem: ConsolidateProblem?) {
        guard !sources.isEmpty else { return (nil, .noSources) }
        let here = activeSheet
        // Keys: a label's lowercase text, or the position when that axis is not labelled.
        func text(_ s: ConsolidateSource, _ r: Int, _ c: Int) -> String {
            let a = CellAddress(row: r, col: c)
            let ws = book.sheets[s.sheet]
            let code = book.style(ws.cells[a]?.style ?? ws.defaultStyle(at: a)).numberFormat
            return NumberFormat.display(ws.value(a), code, width: 255).text
        }
        var rowKeys: [String] = [], colKeys: [String] = []
        var rowLabel: [String: String] = [:], colLabel: [String: String] = [:]
        struct Pick { var rowKey: String; var colKey: String; var src: Int; var row: Int; var col: Int }
        var picks: [Pick] = []
        for (i, s) in sources.enumerated() {
            let r0 = s.range.top + (topRow ? 1 : 0), c0 = s.range.left + (leftColumn ? 1 : 0)
            guard r0 <= s.range.bottom, c0 <= s.range.right else { continue }
            var cKeyOf: [Int: String] = [:]
            for c in c0 ... s.range.right {
                let k: String
                if topRow { let t = text(s, s.range.top, c); if t.isEmpty { continue }; k = t.lowercased(); if colLabel[k] == nil { colLabel[k] = t } }
                else { k = "#\(c - c0)" }
                cKeyOf[c] = k
                if !colKeys.contains(k) { colKeys.append(k) }
            }
            for r in r0 ... s.range.bottom {
                let k: String
                if leftColumn { let t = text(s, r, s.range.left); if t.isEmpty { continue }; k = t.lowercased(); if rowLabel[k] == nil { rowLabel[k] = t } }
                else { k = "#\(r - r0)" }
                if !rowKeys.contains(k) { rowKeys.append(k) }
                for c in c0 ... s.range.right {
                    guard let ck = cKeyOf[c] else { continue }
                    picks.append(Pick(rowKey: k, colKey: ck, src: i, row: r, col: c))
                }
            }
        }
        guard !rowKeys.isEmpty, !colKeys.isEmpty else { return (nil, .nothingToWrite) }
        let dataTop = dest.row + (topRow ? 1 : 0), dataLeft = dest.col + (leftColumn ? 1 : 0)
        guard dataTop + rowKeys.count - 1 < CellAddress.maxRows, dataLeft + colKeys.count - 1 < CellAddress.maxCols else { return (nil, .offSheet) }
        let block = CellRange(top: dest.row, left: dest.col, bottom: dataTop + rowKeys.count - 1, right: dataLeft + colKeys.count - 1)
        if sources.contains(where: { $0.sheet == here && $0.range.intersects(block) }) { return (nil, .overlapsSource) }
        if sheet.merges.contains(where: { $0.intersects(block) }) { return (nil, .mergedCells) }
        if picks.allSatisfy({ book.sheets[sources[$0.src].sheet].value(CellAddress(row: $0.row, col: $0.col)).isEmpty }) { return (nil, .nothingToWrite) }
        var blockCells: [CellAddress] = []
        for r in block.top ... block.bottom { for c in block.left ... block.right { blockCells.append(CellAddress(row: r, col: c)) } }
        if refusesEdit(blockCells) { return (nil, nil) }
        var cellsOf: [String: [Pick]] = [:]
        for p in picks { cellsOf[p.rowKey + "\u{1}" + p.colKey, default: []].append(p) }
        var written = 0
        structural {
            func put(_ a: CellAddress, _ input: String, formula: Bool) {
                var cell = Cell(input: input)
                if formula, let f = try? Formula.parse(input) { cell.formula = f; cell.value = .empty }
                else if let n = Double(input) { cell.value = .number(n) }
                else if !input.isEmpty { cell.value = .text(input) }
                sheet.cells[a] = cell
            }
            for r in block.top ... block.bottom { for c in block.left ... block.right { sheet.cells[CellAddress(row: r, col: c)] = nil } }
            if topRow { for (j, k) in colKeys.enumerated() { put(CellAddress(row: dest.row, col: dataLeft + j), colLabel[k] ?? "", formula: false) } }
            if leftColumn { for (i, k) in rowKeys.enumerated() { put(CellAddress(row: dataTop + i, col: dest.col), rowLabel[k] ?? "", formula: false) } }
            var formulas: [CellAddress] = []
            for (i, rk) in rowKeys.enumerated() {
                for (j, ck) in colKeys.enumerated() {
                    guard let ps = cellsOf[rk + "\u{1}" + ck] else { continue }
                    let live = ps.filter { p in !book.sheets[sources[p.src].sheet].value(CellAddress(row: p.row, col: p.col)).isEmpty }
                    guard !live.isEmpty else { continue }
                    let refs = ps.map { p -> String in
                        let a = CellAddress(row: p.row, col: p.col).a1
                        let sn = sources[p.src].sheet
                        return sn == here ? a : Formula.quoteSheet(book.sheets[sn].name) + "!" + a
                    }
                    let a = CellAddress(row: dataTop + i, col: dataLeft + j)
                    put(a, "=" + function.formulaName + "(" + refs.joined(separator: ",") + ")", formula: true)
                    formulas.append(a)
                }
            }
            engine.recalculate()
            written = formulas.count
            if !link {
                for a in formulas {
                    switch sheet.value(a) {
                    case .number(let n): put(a, n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n), formula: false)
                    case .text(let t): put(a, t, formula: false)
                    case .bool(let b): put(a, b ? "TRUE" : "FALSE", formula: false)
                    default: sheet.cells[a] = nil; written -= 1
                    }
                }
            }
        }
        return (written, nil)
    }
}
