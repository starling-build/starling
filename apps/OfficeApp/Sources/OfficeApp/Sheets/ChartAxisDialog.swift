// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CH-3: Chart Design → Axis Options. The value axis: lowest and highest value, major unit, number format. Empty means automatic.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

final class ChartAxisDialog: StatefulWidget {
    let controller: WorkbookController
    let index: Int
    let onClose: () -> Void
    init(controller: WorkbookController, index: Int, onClose: @escaping () -> Void) {
        self.controller = controller
        self.index = index
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { ChartAxisDialogState() }
}

final class ChartAxisDialogState: State<StatefulWidget> {
    private var _w: ChartAxisDialog { widget as! ChartAxisDialog }
    let min = TextEditingController()
    let max = TextEditingController()
    let major = TextEditingController()
    let format = TextEditingController()
    private var _seeded = false

    private static func show(_ v: Double?) -> String {
        guard let v else { return "" }
        return v == v.rounded() && Swift.abs(v) < 1e15 ? String(Int64(v)) : String(v)
    }

    func apply() {
        func num(_ t: TextEditingController) -> Double? { Double(t.text.trimmingSpaces()) }
        _ = _w.controller.setChartAxis(_w.index, ChartAxisEdit(min: num(min), max: num(max), major: num(major),
                                                              format: format.text.isEmpty ? nil : format.text))
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let o = _w.controller.chartAxisOptions(_w.index)
        if !_seeded {
            _seeded = true
            min.text = Self.show(o?.min); max.text = Self.show(o?.max); major.text = Self.show(o?.major); format.text = o?.format ?? ""
        }
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        func line(_ label: String, _ id: String, _ c: TextEditingController, _ hint: String) -> Widget {
            Row(children: [
                SizedBox(width: 150, height: nil, child: Text(label)),
                SizedBox(width: 220, height: nil, child: FluentTextBox(key: ValueKey(id), controller: c, placeholderText: hint)),
            ])
        }
        var rows: [Widget] = []
        if o != nil {
            rows = [Text("Value axis (leave empty for automatic)"), gap(8),
                    line("Minimum:", "chartaxis-min", min, "Auto"), gap(8),
                    line("Maximum:", "chartaxis-max", max, "Auto"), gap(8),
                    line("Major unit:", "chartaxis-major", major, "Auto"), gap(8),
                    line("Number format:", "chartaxis-format", format, "General, 0.00, 0%, #,##0")]
        } else { rows = [Text("This chart's axis cannot be changed here.")] }
        return DialogShell(title: "Axis Options", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                           okLabel: "OK", cancelLabel: "Cancel", width: 430,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
