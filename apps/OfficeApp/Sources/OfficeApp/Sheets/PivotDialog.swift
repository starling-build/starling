// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-8: Insert → PivotTable. Pick the source range, then for each heading whether it is a row, a column,
// a value (sum, count or average) or a filter, and where the table goes.

import Flutter
import FlutterSwiftBridge
import Foundation

final class PivotDialog: StatefulWidget {
    let controller: WorkbookController
    let onClose: () -> Void

    init(controller: WorkbookController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { PivotDialogState() }
}

final class PivotDialogState: State<StatefulWidget> {
    private var _w: PivotDialog { widget as! PivotDialog }
    private let _source = TextEditingController()
    private let _dest = TextEditingController()
    private(set) var fields: [String] = []
    private(set) var rows: [Int] = []
    private(set) var cols: [Int] = []
    private(set) var values: [Int: PivotFunction] = [:]
    private(set) var filters: [Int] = []
    private(set) var newSheet = true
    private(set) var message = ""

    override func initState() {
        super.initState()
        let c = _w.controller
        let region = c.currentRegion(CellAddress(row: c.selection.top, col: c.selection.left))
        _source.text = Formula.quoteSheet(c.sheet.name) + "!" + region.a1
        _dest.text = "A1"
        readFields()
    }

    func readFields() {
        let f = _w.controller.pivotFields(source: _source.text) ?? []
        if f != fields { fields = f; rows = []; cols = []; values = [:]; filters = [] }
    }

    /// A heading has one job: take it out of the others first.
    func toggle(_ job: Int, _ i: Int, _ on: Bool) {
        setState {
            rows.removeAll { $0 == i }; cols.removeAll { $0 == i }; filters.removeAll { $0 == i }; values[i] = nil
            guard on else { return }
            if job == 0 { rows.append(i) } else if job == 1 { cols.append(i) } else { filters.append(i) }
        }
    }

    func setValue(_ i: Int, _ on: Bool) {
        setState {
            if on { rows.removeAll { $0 == i }; cols.removeAll { $0 == i }; filters.removeAll { $0 == i }; values[i] = values[i] ?? .sum }
            else { values[i] = nil }
        }
    }

    func cycle(_ i: Int) {
        setState { values[i] = values[i] == .sum ? .count : values[i] == .count ? .average : .sum }
    }

    func ok() {
        readFields()
        guard !fields.isEmpty else { message = PivotProblem.noSource.message; setState {}; return }
        var origin = CellAddress(row: 0, col: 0)
        if !newSheet {
            guard let a = CellAddress(_dest.text.trimmingWhitespace()) else { message = "Type the cell where the table starts, like F2."; setState {}; return }
            origin = a
        }
        let data = values.keys.sorted().map { PivotDataField(field: $0, function: values[$0]!) }
        let p = _w.controller.insertPivotTable(
            source: _source.text, rows: rows, cols: cols, data: data,
            filters: filters.map { PivotFilter(field: $0, item: nil) }, origin: origin, newSheet: newSheet)
        if let p { message = p.message; setState {}; return }
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        var list: [Widget] = [
            Text("Range", style: fluent.typography.caption), gap(4),
            SizedBox(width: nil, height: Chrome.fieldHeight, child: FluentTextBox(
                key: ValueKey("pivot-source"), controller: _source, placeholderText: "Sheet1!A1:C20",
                onChanged: { [weak self] _ in self?.setState { self?.readFields() } })),
            gap(8), Text("Use each heading as:", style: fluent.typography.bodyStrong), gap(4),
        ]
        if fields.isEmpty { list += [Text("Type a range whose first row holds headings.", style: fluent.typography.caption)] }
        else if !PivotSpec.offersFilters { list += [Text("Filters (report filter fields) are not offered yet.", style: fluent.typography.caption), gap(4)] }
        for (i, name) in fields.enumerated() {
            let fn = values[i]
            list.append(Text(name.isEmpty ? "Column \(i + 1)" : name, style: fluent.typography.body))
            var choices: [Widget] = [
                Checkbox(key: ValueKey("pivot-row-\(i)"), checked: rows.contains(i), onChanged: { [weak self] v in self?.toggle(0, i, v ?? false) }, content: Text("Row")),
                SizedBox(width: 8, height: nil, child: nil),
                Checkbox(key: ValueKey("pivot-col-\(i)"), checked: cols.contains(i), onChanged: { [weak self] v in self?.toggle(1, i, v ?? false) }, content: Text("Column")),
                SizedBox(width: 8, height: nil, child: nil),
                Checkbox(key: ValueKey("pivot-val-\(i)"), checked: fn != nil, onChanged: { [weak self] v in self?.setValue(i, v ?? false) }, content: Text("Value")),
            ]
            // Page fields are held back while Excel crashes on the ones we write.
            if PivotSpec.offersFilters {
                choices.append(SizedBox(width: 8, height: nil, child: nil))
                choices.append(Checkbox(key: ValueKey("pivot-flt-\(i)"), checked: filters.contains(i), onChanged: { [weak self] v in self?.toggle(2, i, v ?? false) }, content: Text("Filter")))
            }
            list.append(Row(children: choices))
            if let fn {
                list.append(Button(key: ValueKey("pivot-fn-\(i)"), onPressed: { [weak self] in self?.cycle(i) },
                                   child: Text(String(fn.caption.dropLast(4)) + " (click to change)")))
            }
            list.append(gap(4))
        }
        list += [gap(4), Text("Put the PivotTable in:", style: fluent.typography.bodyStrong), gap(4),
                 Checkbox(key: ValueKey("pivot-new"), checked: newSheet, onChanged: { [weak self] v in self?.setState { self?.newSheet = v ?? true } }, content: Text("A new worksheet"))]
        if !newSheet {
            list += [gap(4), Text("Starting at cell", style: fluent.typography.caption), gap(4),
                     SizedBox(width: nil, height: Chrome.fieldHeight, child: FluentTextBox(key: ValueKey("pivot-dest"), controller: _dest, placeholderText: "F2"))]
        }
        list += [gap(6), Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C)))]
        return DialogShell(
            title: "Create PivotTable",
            page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: list),
            okLabel: "OK", cancelLabel: "Cancel", okEnabled: true, width: 440,
            onOK: { [weak self] in self?.ok() }, onCancel: _w.onClose)
    }
}
