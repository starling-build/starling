// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The PivotTable Fields pane: beside the grid while the active cell is in a PivotTable made here. Tick a field to add it (text to
// Rows, numbers to Values, as Excel does); each field in Filters, Columns, Rows or Values can be moved to the next area, up or down
// in its area, or taken out. Fields drag with the pointer from the list or between the areas (dropped on a field, one goes before it);
// the buttons are the keyboard path.

import Flutter
import FlutterSwiftBridge
import Foundation

/// The four areas, in the order the pane lists them.
enum PivotArea: Int, CaseIterable {
    case filters, columns, rows, values
    var title: String { ["Filters", "Columns", "Rows", "Values"][rawValue] }
}

extension WorkbookController {
    /// The fields of the pivot made here under the active cell, as the pane shows them; nil when the active cell is in none.
    func pivotPaneState() -> (index: Int, fields: [String], numeric: [Bool], spec: PivotSpec)? {
        let ws = sheet
        guard let k = madePivotIndex(on: ws, at: active), let spec = ws.pivots[k].made, let s = ws.pivots[k].source,
              let src = PivotSource.read(s, book: book) else { return nil }
        let numeric = src.headers.indices.map { c -> Bool in
            let col = src.rows.map { $0[c] }.filter { $0 != .empty }
            return !col.isEmpty && col.allSatisfy { if case .number = $0 { return true } else { return false } }
        }
        return (k, src.headers, numeric, spec)
    }

    /// Move field `f` to `area` (nil: out of the table), at `position` there (nil: the end). A field is in one area, except that a
    /// number may also stay in Values while it sits in another. Returns the problem when the table cannot be laid out so.
    @discardableResult
    /// Value Field Settings: replace the settings of the pivot's `k`th value field.
    func setPivotValueField(_ k: Int, _ d: PivotDataField) -> PivotProblem? {
        guard let st = pivotPaneState(), st.spec.data.indices.contains(k) else { return .noSource }
        var data = st.spec.data
        data[k] = d
        return setPivotFields(sheet: sheet, pivot: st.index, rows: st.spec.rows, cols: st.spec.cols, data: data, filters: st.spec.filters)
    }

    func movePivotField(_ f: Int, to area: PivotArea?, at position: Int? = nil) -> PivotProblem? {
        guard let st = pivotPaneState() else { return .noSource }
        var rows = st.spec.rows, cols = st.spec.cols, filters = st.spec.filters, data = st.spec.data
        if area != .values { data.removeAll { $0.field == f } }
        if area != nil { rows.removeAll { $0 == f }; cols.removeAll { $0 == f }; filters.removeAll { $0.field == f } }
        else { rows.removeAll { $0 == f }; cols.removeAll { $0 == f }; filters.removeAll { $0.field == f } }
        func put<T>(_ a: inout [T], _ x: T) { a.insert(x, at: min(position ?? a.count, a.count)) }
        switch area {
        case .rows: put(&rows, f)
        case .columns: put(&cols, f)
        case .filters: put(&filters, PivotFilter(field: f, item: nil))
        case .values: if !data.contains(where: { $0.field == f }) { put(&data, PivotDataField(field: f, function: .sum)) }
        case nil: break
        }
        return setPivotFields(sheet: sheet, pivot: st.index, rows: rows, cols: cols, data: data, filters: filters)
    }

    /// Swap field `f` with its neighbour in its area (`by` -1 up, +1 down).
    @discardableResult
    func shiftPivotField(_ f: Int, in area: PivotArea, by: Int) -> PivotProblem? {
        guard let st = pivotPaneState() else { return .noSource }
        var rows = st.spec.rows, cols = st.spec.cols, filters = st.spec.filters, data = st.spec.data
        func swap<T>(_ a: inout [T], _ i: Int?) { if let i, a.indices.contains(i + by) { a.swapAt(i, i + by) } }
        switch area {
        case .rows: swap(&rows, rows.firstIndex(of: f))
        case .columns: swap(&cols, cols.firstIndex(of: f))
        case .filters: swap(&filters, filters.firstIndex { $0.field == f })
        case .values: swap(&data, data.firstIndex { $0.field == f })
        }
        return setPivotFields(sheet: sheet, pivot: st.index, rows: rows, cols: cols, data: data, filters: filters)
    }
}

final class PivotFieldsPane: StatelessWidget {
    let controller: WorkbookController
    let onChange: () -> Void
    /// Opens Value Field Settings for the value field at this position.
    let onValueSettings: ((Int) -> Void)?
    /// Open the Group dialog for a field (given by its source column).
    let onGroup: ((Int) -> Void)?
    init(controller: WorkbookController, onChange: @escaping () -> Void, onValueSettings: ((Int) -> Void)? = nil, onGroup: ((Int) -> Void)? = nil) {
        self.controller = controller; self.onChange = onChange; self.onValueSettings = onValueSettings; self.onGroup = onGroup
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        guard let st = controller.pivotPaneState() else { return SizedBox(width: 0, height: 0, child: nil) }
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        func name(_ i: Int) -> String { st.fields[i].isEmpty ? "Column \(i + 1)" : st.fields[i] }
        func area(_ f: Int) -> PivotArea? {
            st.spec.filters.contains { $0.field == f } ? .filters : st.spec.cols.contains(f) ? .columns : st.spec.rows.contains(f) ? .rows : nil
        }
        func ghost(_ f: Int) -> Widget {
            ColoredBox(color: fluent.accentColor.defaultBrushFor(fluent.brightness), child: Padding(padding: EdgeInsets(all: 6), child: Text(name(f))))
        }
        func draggable(_ f: Int, _ child: Widget) -> Widget { Draggable<Int>(data: f, child: child, feedback: ghost(f)) }
        var list: [Widget] = [Text("PivotTable Fields", style: fluent.typography.bodyStrong), gap(6), Text("Choose fields to add to the report:", style: fluent.typography.caption)]
        for i in st.fields.indices {
            let on = area(i) != nil || st.spec.data.contains { $0.field == i }
            list.append(draggable(i, Checkbox(key: ValueKey("pvf-field-\(i)"), checked: on, onChanged: { [weak self] v in
                guard let self else { return }
                self.controller.movePivotField(i, to: (v ?? false) ? (st.numeric[i] ? .values : .rows) : nil)
                self.onChange()
            }, content: Text(name(i)))))
        }
        func chips(_ a: PivotArea, _ items: [Int]) {
            var block: [Widget] = [gap(8), Text(a.title, style: fluent.typography.bodyStrong)]
            if items.isEmpty { block.append(Text("(none)", style: fluent.typography.caption)) }
            for (at, f) in items.enumerated() {
                var next = PivotArea(rawValue: (a.rawValue + 1) % 4)!
                if next == .filters && !PivotSpec.offersFilters { next = .columns }
                var label = name(f)
                if a == .values, let d = st.spec.data.first(where: { $0.field == f }) { label = d.name ?? d.function.caption + label }
                var buttons: [Widget] = []
                if a == .values, let open = onValueSettings {
                    buttons.append(Button(key: ValueKey("pvf-settings-\(f)"), onPressed: { open(at) }, child: Text("⚙")))
                }
                if a == .rows || a == .columns, let open = onGroup {
                    buttons.append(Button(key: ValueKey("pvf-group-\(f)"), onPressed: { open(f) }, child: Text("▦")))
                }
                let chip = Row(children: [
                    Expanded(child: Text(label, style: fluent.typography.body)),
                ] + buttons + [
                    Button(key: ValueKey("pvf-up-\(a.rawValue)-\(f)"), onPressed: { [weak self] in self?.controller.shiftPivotField(f, in: a, by: -1); self?.onChange() }, child: Text("↑")),
                    Button(key: ValueKey("pvf-down-\(a.rawValue)-\(f)"), onPressed: { [weak self] in self?.controller.shiftPivotField(f, in: a, by: 1); self?.onChange() }, child: Text("↓")),
                    Button(key: ValueKey("pvf-move-\(a.rawValue)-\(f)"), onPressed: { [weak self] in self?.controller.movePivotField(f, to: next); self?.onChange() }, child: Text("→ " + next.title)),
                    Button(key: ValueKey("pvf-out-\(a.rawValue)-\(f)"), onPressed: { [weak self] in self?.controller.movePivotField(f, to: nil); self?.onChange() }, child: Text("✕")),
                ])
                // Dropped on a field, a dragged one goes before it.
                block.append(DragTarget<Int>(key: ValueKey("pvf-slot-\(a.rawValue)-\(f)"), builder: { _, _, _ in draggable(f, chip) },
                                             onAccept: { [weak self] d in self?.controller.movePivotField(d, to: a, at: at); self?.onChange() }))
            }
            list.append(DragTarget<Int>(key: ValueKey("pvf-area-\(a.rawValue)"), builder: { _, over, _ in
                ColoredBox(color: over.isEmpty ? Color(0x00000000) : fluent.accentColor.defaultBrushFor(fluent.brightness).withOpacity(0.15), child: Column(crossAxisAlignment: .stretch, children: block))
            }, onAccept: { [weak self] d in self?.controller.movePivotField(d, to: a); self?.onChange() }))
        }
        if PivotSpec.offersFilters || !st.spec.filters.isEmpty { chips(.filters, st.spec.filters.map(\.field)) }; chips(.columns, st.spec.cols); chips(.rows, st.spec.rows); chips(.values, st.spec.data.map(\.field))
        return SizedBox(width: 300, height: nil, child: ColoredBox(color: fluent.scaffoldBackgroundColor,
            child: Padding(padding: EdgeInsets(all: 10), child: SingleChildScrollView(child: Column(crossAxisAlignment: .stretch, children: list)))))
    }
}
