// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-SE-1: Go To Special (Home → Find & Select → Go To Special…, or Special… in Go To). Selects the
// cells of one kind as a multi-range selection: notes, constants or formulas (numbers, text,
// logicals, errors), blanks, the current region, the last cell, visible cells only, conditional
// formats or data validation (all, or the same as the active cell's). As Excel: a selection of more
// than one cell is searched; a single cell searches the sheet's used range.

import Flutter
import FlutterSwiftBridge
import Foundation

enum GoToSpecialKind: Int, CaseIterable {
    case notes, constants, formulas, blanks, currentRegion, lastCell, visibleOnly, conditionalFormats, dataValidation
    var label: String {
        ["Notes", "Constants", "Formulas", "Blanks", "Current region", "Last cell", "Visible cells only",
         "Conditional formats", "Data validation"][rawValue]
    }
}

struct GoToSpecialOptions: Equatable {
    var kind = GoToSpecialKind.constants
    /// Constants and Formulas: which values count.
    var numbers = true, text = true, logicals = true, errors = true
    /// Conditional formats and Data validation: Same (as the active cell's) rather than All.
    var same = false
}

extension WorkbookController {
    /// Select what `o` names; nil when done, else Excel's message ("No cells were found.").
    @discardableResult
    func goToSpecial(_ o: GoToSpecialOptions) -> String? {
        let ws = sheet
        let used = ws.usedExtent
        let usedRange = CellRange(top: 0, left: 0, bottom: used.row, right: used.col)
        // A selection of more than one cell is the scope; one cell means the whole sheet (its used part).
        let searchSel = isMultiRange || !selection.isSingle
        let scope: [CellRange] = searchSel ? selectedRanges : [CellRange(top: 0, left: 0, bottom: CellAddress.maxRows - 1, right: CellAddress.maxCols - 1)]
        // Cell kinds only look where cells can be: the scope cut to the used range.
        let cellScope = scope.compactMap { $0.intersection(usedRange) }
        var found: [CellRange] = []
        switch o.kind {
        case .currentRegion:
            select(range: currentRegion(active), active: active)
            return nil
        case .lastCell:
            // Excel's last cell: the bottom row and right column used, held or formatted.
            let a = CellAddress(row: used.row, col: used.col)
            select(range: CellRange(a), active: a)
            return nil
        case .notes:
            let cells = Set(ws.notes.compactMap(\.at).filter { a in scope.contains { $0.contains(a) } })
            found = Self.rectangles(cells)
        case .constants, .formulas:
            let wantFormula = o.kind == .formulas
            var cells = Set<CellAddress>()
            for (a, c) in ws.cells where (c.formula != nil) == wantFormula && cellScope.contains(where: { $0.contains(a) }) {
                switch c.value {
                case .empty: continue
                case .number: if o.numbers { cells.insert(a) }
                case .text: if o.text { cells.insert(a) }
                case .bool: if o.logicals { cells.insert(a) }
                case .error: if o.errors { cells.insert(a) }
                }
            }
            found = Self.rectangles(cells)
        case .blanks:
            // Empty cells inside the used range (a formula giving "" is not blank).
            var cells = Set<CellAddress>()
            for r in cellScope where r.area <= 4_000_000 {
                for row in r.top ... r.bottom {
                    for col in r.left ... r.right {
                        let a = CellAddress(row: row, col: col)
                        if let c = ws.cells[a], !c.value.isEmpty || c.formula != nil { continue }
                        cells.insert(a)
                    }
                }
            }
            found = Self.rectangles(cells)
        case .visibleOnly:
            // Each scope range cut into its runs of shown rows and columns.
            let base = searchSel ? scope : [usedRange]
            for r in base {
                let rowRuns = Self._runs(r.top, r.bottom) { !ws.isRowHidden($0) }
                let colRuns = Self._runs(r.left, r.right) { !ws.isColHidden($0) }
                for rr in rowRuns { for cc in colRuns { found.append(CellRange(top: rr.0, left: cc.0, bottom: rr.1, right: cc.1)) } }
            }
        case .conditionalFormats:
            var rules = ConditionalFormats.rules(ws, theme: book.themeColors)
            if o.same { rules = rules.filter { $0.ranges.contains { $0.contains(active) } } }
            found = Self._clip(rules.flatMap(\.ranges), to: scope)
        case .dataValidation:
            var rules = validationRules
            if o.same { rules = rules.filter { $0.ranges.contains { $0.contains(active) } } }
            found = Self._clip(rules.flatMap(\.ranges), to: scope)
        }
        guard let first = found.first else { return "No cells were found." }
        // The active cell stays where it is when it is among the found cells (Excel's), else the first found.
        let keep = found.firstIndex { $0.contains(active) }
        var ranges = found
        let act: CellAddress
        if let k = keep { act = active; ranges.append(ranges.remove(at: k)) } else { act = first.topLeft; ranges.append(ranges.removeFirst()) }
        select(ranges: ranges, active: act)
        return nil
    }

    /// `ranges` cut to `scope`, without overlaps (a cell in two rules' ranges is selected once).
    static func _clip(_ ranges: [CellRange], to scope: [CellRange]) -> [CellRange] {
        var out: [CellRange] = []
        for r in ranges {
            for s in scope {
                guard let x = r.intersection(s) else { continue }
                var pieces = [x]
                for o in out { pieces = pieces.flatMap { _subtract($0, o) } }
                out += pieces
            }
        }
        return out
    }

    /// The runs of `lo ... hi` where `keep` holds, as (first, last) pairs.
    static func _runs(_ lo: Int, _ hi: Int, _ keep: (Int) -> Bool) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        var start: Int? = nil
        // A whole column or row: hidden ones are few, so jump over long shown stretches by checking each index
        // only up to the sheet's limits (1,048,576 rows is still a quick loop of Bool checks).
        for i in lo ... hi {
            if keep(i) { if start == nil { start = i } } else if let s = start { out.append((s, i - 1)); start = nil }
        }
        if let s = start { out.append((s, hi)) }
        return out
    }

    /// Cells as rectangles, top to bottom: runs along each row, then equal runs on rows below joined.
    static func rectangles(_ cells: Set<CellAddress>) -> [CellRange] {
        var byRow: [Int: [Int]] = [:]
        for a in cells { byRow[a.row, default: []].append(a.col) }
        var open: [Int: CellRange] = [:]   // keyed by left column, runs still growing downward
        var done: [CellRange] = []
        var lastRow = Int.min
        for row in byRow.keys.sorted() {
            if row != lastRow + 1 { done += open.values; open = [:] }
            lastRow = row
            var runs: [(Int, Int)] = []
            for c in byRow[row]!.sorted() {
                if let l = runs.last, l.1 == c - 1 { runs[runs.count - 1].1 = c } else { runs.append((c, c)) }
            }
            var next: [Int: CellRange] = [:]
            for (l, r) in runs {
                if var o = open[l], o.right == r { o.bottom = row; next[l] = o; open[l] = nil }
                else { next[l] = CellRange(top: row, left: l, bottom: row, right: r) }
            }
            done += open.values
            open = next
        }
        done += open.values
        return done.sorted { ($0.top, $0.left) < ($1.top, $1.left) }
    }
}

final class GoToSpecialDialog: StatefulWidget {
    let controller: WorkbookController
    let onClose: () -> Void
    init(controller: WorkbookController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { GoToSpecialDialogState() }
}

final class GoToSpecialDialogState: State<StatefulWidget> {
    private var _w: GoToSpecialDialog { widget as! GoToSpecialDialog }
    private(set) var options = GoToSpecialOptions()
    private(set) var message = ""

    func set(_ change: (inout GoToSpecialOptions) -> Void) { change(&options); message = ""; setState {} }

    func apply() {
        if let m = _w.controller.goToSpecial(options) { message = m; setState {}; return }
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func radio(_ k: GoToSpecialKind) -> Widget {
            RadioButton<GoToSpecialKind>(key: ValueKey("gts-\(k.rawValue)"), value: k, groupValue: options.kind,
                                         onChanged: { [weak self] _ in self?.set { $0.kind = k } }, content: Text(k.label))
        }
        func sub(_ id: String, _ label: String, _ on: Bool, enabled: Bool, _ flip: @escaping (inout GoToSpecialOptions) -> Void) -> Widget {
            Padding(padding: EdgeInsets(left: 28, top: 2, right: 0, bottom: 2), child:
                Checkbox(key: ValueKey(id), checked: on, onChanged: enabled ? { [weak self] _ in self?.set(flip) } : nil, content: Text(label)))
        }
        func subRadio(_ id: String, _ label: String, same: Bool, enabled: Bool) -> Widget {
            Padding(padding: EdgeInsets(left: 28, top: 2, right: 0, bottom: 2), child:
                RadioButton<Bool>(key: ValueKey(id), value: same, groupValue: options.same,
                                  onChanged: enabled ? { [weak self] _ in self?.set { $0.same = same } } : nil, content: Text(label)))
        }
        let kinds = options.kind == .constants || options.kind == .formulas
        let rulesOn = options.kind == .conditionalFormats || options.kind == .dataValidation
        let gap = SizedBox(width: nil, height: 6, child: nil)
        let left = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
            radio(.notes), gap, radio(.constants), gap, radio(.formulas),
            sub("gts-numbers", "Numbers", options.numbers, enabled: kinds) { $0.numbers.toggle() },
            sub("gts-text", "Text", options.text, enabled: kinds) { $0.text.toggle() },
            sub("gts-logicals", "Logicals", options.logicals, enabled: kinds) { $0.logicals.toggle() },
            sub("gts-errors", "Errors", options.errors, enabled: kinds) { $0.errors.toggle() },
            gap, radio(.blanks), gap, radio(.currentRegion),
        ])
        let right = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
            radio(.lastCell), gap, radio(.visibleOnly), gap, radio(.conditionalFormats), gap, radio(.dataValidation),
            subRadio("gts-all", "All", same: false, enabled: rulesOn),
            subRadio("gts-same", "Same", same: true, enabled: rulesOn),
        ])
        let page = Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: [
            Text("Select", style: fluent.typography.body), SizedBox(width: nil, height: 8, child: nil),
            Row(crossAxisAlignment: .start, children: [Expanded(child: left), Expanded(child: right)]),
            SizedBox(width: nil, height: 6, child: nil),
            Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C))),
        ])
        return DialogShell(title: "Go To Special", page: page, okLabel: "OK", cancelLabel: "Cancel", width: 420,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
