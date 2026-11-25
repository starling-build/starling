// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Value Field Settings: the custom name, the function (Sum, Count, Average, Min, Max), Show Values As
// and the number format of one value field of a PivotTable.

import Flutter
import FlutterSwiftBridge
import Foundation

final class PivotValueFieldDialog: StatefulWidget {
    let controller: WorkbookController
    /// Which of the pivot's value fields (its position in Values).
    let index: Int
    let onClose: () -> Void

    init(controller: WorkbookController, index: Int, onClose: @escaping () -> Void) {
        self.controller = controller
        self.index = index
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { PivotValueFieldDialogState() }
}

final class PivotValueFieldDialogState: State<StatefulWidget> {
    private var _w: PivotValueFieldDialog { widget as! PivotValueFieldDialog }
    /// The formats offered: label and code ("" is General).
    static let formats: [(label: String, code: String)] = [
        ("General", ""), ("Number", "#,##0.00"), ("Currency", "$#,##0.00"), ("Percentage", "0.00%"), ("Integer", "0"),
    ]
    let nameBox = TextEditingController()
    private(set) var function = PivotFunction.sum
    private(set) var showAs = PivotShowAs.normal
    private(set) var format = ""
    private(set) var message = ""
    private var _seeded = false
    private var _field = 0
    private var _seededName = ""

    func setFunction(_ f: PivotFunction) { function = f; setState {} }
    func setShowAs(_ s: PivotShowAs) { showAs = s; setState {} }
    func setFormat(_ f: String) { format = f; setState {} }

    func apply() {
        var d = PivotDataField(field: _field, function: function)
        let n = nameBox.text.trimmingWhitespace()
        // (The name left as the one offered is not a custom one: it follows the function.)
        d.name = n.isEmpty || n == _seededName ? nil : n
        d.showAs = showAs
        if d.numberFormat != (format.isEmpty ? nil : format) { d.fileFormatId = nil }
        d.numberFormat = format.isEmpty ? nil : format
        if let p = _w.controller.setPivotValueField(_w.index, d) { message = p.message; setState {}; return }
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        if !_seeded, let st = _w.controller.pivotPaneState(), st.spec.data.indices.contains(_w.index) {
            _seeded = true
            let d = st.spec.data[_w.index]
            _field = d.field; function = d.function; showAs = d.showAs; format = d.numberFormat ?? ""
            _seededName = d.function.caption + st.fields[d.field]
            nameBox.text = d.name ?? _seededName
        }
        let fluent = FluentTheme.of(context)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        let source = _w.controller.pivotPaneState().map { $0.fields.indices.contains(_field) ? $0.fields[_field] : "" } ?? ""
        let rows: [Widget] = [
            Text("Source Name: " + source, style: fluent.typography.body),
            gap(8),
            Text("Custom Name:", style: fluent.typography.body), gap(4),
            SizedBox(width: 300, height: nil, child: FluentTextBox(key: ValueKey("pvv-name"), controller: nameBox, placeholderText: "")),
            gap(8),
            Text("Summarize value field by:", style: fluent.typography.body), gap(4),
            SizedBox(width: 300, height: nil, child: ComboBox<String>(
                key: ValueKey("pvv-function"), value: function.rawValue,
                items: PivotFunction.allCases.map { ComboBoxItem<String>(value: $0.rawValue, child: Text($0.title)) },
                onChanged: { [weak self] v in if let v, let f = PivotFunction(rawValue: v) { self?.setFunction(f) } })),
            gap(8),
            Text("Show values as:", style: fluent.typography.body), gap(4),
            SizedBox(width: 300, height: nil, child: ComboBox<String>(
                key: ValueKey("pvv-showas"), value: showAs.rawValue,
                items: PivotShowAs.allCases.map { ComboBoxItem<String>(value: $0.rawValue, child: Text($0.title)) },
                onChanged: { [weak self] v in if let v, let s = PivotShowAs(rawValue: v) { self?.setShowAs(s) } })),
            gap(8),
            Text("Number format:", style: fluent.typography.body), gap(4),
            SizedBox(width: 300, height: nil, child: ComboBox<String>(
                key: ValueKey("pvv-format"), value: format,
                items: Self.formats.map { ComboBoxItem<String>(value: $0.code, child: Text($0.label)) },
                onChanged: { [weak self] v in if let v { self?.setFormat(v) } })),
            gap(6),
            Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C))),
        ]
        return DialogShell(title: "Value Field Settings", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                           okLabel: "OK", cancelLabel: "Cancel", width: 380,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
