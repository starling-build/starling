// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-5: Insert → Table. With the active cell outside any table it asks for the range and
// whether the first row is a header row, then makes the table (createTable). Inside a table
// it shows that table's options: style, banded rows and columns, first and last column, the
// totals row, its range, and Convert to Range. Each change applies at once and is its own
// undo step, as Excel's Table Design checkboxes are.

import Flutter
import FlutterSwiftBridge
import Foundation

final class TableDialog: StatefulWidget {
    let controller: WorkbookController
    let onClose: () -> Void

    init(controller: WorkbookController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { TableDialogState() }
}

final class TableDialogState: State<StatefulWidget> {
    private var _w: TableDialog { widget as! TableDialog }

    /// The table being edited (an index into the sheet's tables); nil: making a new one.
    private(set) var index: Int?
    private(set) var hasHeaders = true
    private(set) var style = "TableStyleMedium2"
    private(set) var message = ""
    private let _range = TextEditingController()
    private let _resize = TextEditingController()

    override func initState() {
        super.initState()
        let c = _w.controller
        if let i = c.tableIndex(at: c.active) {
            index = i
            _resize.text = c.sheet.tables[i].ref.a1
        } else if let region = c.sortRegion() {
            _range.text = region.range.a1
            hasHeaders = region.hasHeader
        } else {
            _range.text = c.selection.a1
        }
    }

    func setHeaders(_ on: Bool) { setState { hasHeaders = on } }
    func setStyle(_ s: String) {
        style = s
        if let i = index { _w.controller.setTableLook(at: i, style: .some(s)) }
        setState {}
    }

    private func _parse(_ text: String) -> CellRange? { CellRange(text.replacingAll("$", with: "").replacingAll(" ", with: "")) }

    func create() {
        guard let r = _parse(_range.text) else { message = TableProblem.noRange.message; setState {}; return }
        if let p = _w.controller.createTable(r, hasHeaders: hasHeaders, style: style) { message = p.message; setState {} }
        else { _w.onClose() }
    }

    func toggle(_ what: String, _ on: Bool) {
        guard let i = index else { return }
        let c = _w.controller
        message = ""
        switch what {
        case "rows": c.setTableLook(at: i, rowStripes: on)
        case "cols": c.setTableLook(at: i, columnStripes: on)
        case "first": c.setTableLook(at: i, firstColumn: on)
        case "last": c.setTableLook(at: i, lastColumn: on)
        default:
            if let p = c.setTableTotals(at: i, on: on) { message = p.message }
            _resize.text = c.sheet.tables[i].ref.a1
        }
        setState {}
    }

    func resize() {
        guard let i = index else { return }
        guard let r = _parse(_resize.text) else { message = TableProblem.noRange.message; setState {}; return }
        message = _w.controller.resizeTable(at: i, to: r)?.message ?? ""
        _resize.text = _w.controller.sheet.tables[i].ref.a1
        setState {}
    }

    func convert() {
        guard let i = index else { return }
        _w.controller.convertTableToRange(at: i)
        _w.onClose()
    }

    private func _gap(_ h: Double = 8) -> Widget { SizedBox(width: nil, height: h, child: nil) }
    private func _field(_ id: String, _ c: TextEditingController, _ submit: @escaping () -> Void) -> Widget {
        SizedBox(width: nil, height: Chrome.fieldHeight, child: FluentTextBox(
            key: ValueKey(id), controller: c, placeholderText: "", onSubmitted: { _ in submit() }))
    }
    private func _styleCombo() -> Widget {
        SizedBox(width: 260, height: nil, child: ComboBox<String>(
            key: ValueKey("table-style"), value: style,
            items: WorkbookController.tableStyleNames.map { n in
                ComboBoxItem<String>(value: n, child: Text(String(n.dropFirst("TableStyle".count))))
            },
            onChanged: { [weak self] v in if let v { self?.setStyle(v) } }))
    }
    private func _check(_ id: String, _ label: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> Widget {
        Checkbox(key: ValueKey(id), checked: on, onChanged: { v in set(v ?? false) }, content: Text(label))
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let c = _w.controller
        var rows: [Widget] = []
        if let i = index, c.sheet.tables.indices.contains(i) {
            let t = c.sheet.tables[i]
            style = t.style ?? style
            rows += [Text("Table \(t.name)", style: fluent.typography.caption), _gap(), _styleCombo(), _gap(),
                     _check("table-rows", "Banded Rows", t.rowStripes) { [weak self] in self?.toggle("rows", $0) }, _gap(4),
                     _check("table-cols", "Banded Columns", t.columnStripes) { [weak self] in self?.toggle("cols", $0) }, _gap(4),
                     _check("table-first", "First Column", t.firstColumn) { [weak self] in self?.toggle("first", $0) }, _gap(4),
                     _check("table-last", "Last Column", t.lastColumn) { [weak self] in self?.toggle("last", $0) }, _gap(4),
                     _check("table-totals", "Total Row", t.totalsRow) { [weak self] in self?.toggle("totals", $0) }, _gap(),
                     Text("Table range", style: fluent.typography.caption), _gap(4), _field("table-range", _resize) { [weak self] in self?.resize() }, _gap(6),
                     Row(children: [
                        Button(key: ValueKey("table-resize"), onPressed: { [weak self] in self?.resize() }, child: Text("Resize Table")),
                        SizedBox(width: 8, height: nil, child: nil),
                        Button(key: ValueKey("table-convert"), onPressed: { [weak self] in self?.convert() }, child: Text("Convert to Range")),
                     ])]
        } else {
            rows += [Text("Where is the data for your table?", style: fluent.typography.caption), _gap(4),
                     _field("table-source", _range) { [weak self] in self?.create() }, _gap(),
                     _check("table-headers", "My table has headers", hasHeaders) { [weak self] in self?.setHeaders($0) }, _gap(),
                     Text("Style", style: fluent.typography.caption), _gap(4), _styleCombo()]
        }
        rows += [_gap(6), Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C)))]
        let editing = index != nil
        return DialogShell(
            title: editing ? "Table Options" : "Create Table",
            page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
            okLabel: editing ? "Close" : "OK", cancelLabel: editing ? "Close" : "Cancel", okEnabled: true, width: 380,
            onOK: { [weak self] in if editing { self?._w.onClose() } else { self?.create() } }, onCancel: _w.onClose)
    }
}
