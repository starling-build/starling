// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CH-1d: Chart Design → Edit Titles. The chart title and the two axis titles typed by hand; an empty box takes that title off.

import Flutter
import FlutterSwiftBridge
import Foundation

final class ChartTitlesDialog: StatefulWidget {
    let controller: WorkbookController
    let index: Int
    let onClose: () -> Void
    init(controller: WorkbookController, index: Int, onClose: @escaping () -> Void) {
        self.controller = controller
        self.index = index
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { ChartTitlesDialogState() }
}

final class ChartTitlesDialogState: State<StatefulWidget> {
    private var _w: ChartTitlesDialog { widget as! ChartTitlesDialog }
    let title = TextEditingController()
    let category = TextEditingController()
    let value = TextEditingController()
    private var _seeded = false

    private var chart: Chart? {
        let c = _w.controller
        guard c.sheet.drawings.indices.contains(_w.index), case .chart(let sc) = c.sheet.drawings[_w.index].kind else { return nil }
        return sc.chart
    }

    func apply() {
        func text(_ t: TextEditingController) -> String? { t.text.isEmpty ? nil : t.text }
        _w.controller.setChartTitles(_w.index, title: text(title), category: text(category), value: text(value))
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let chart = self.chart
        if !_seeded {
            _seeded = true
            title.text = chart?.title ?? ""
            category.text = chart?.categoryAxisTitle ?? ""
            value.text = chart?.valueAxisTitle ?? ""
        }
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        func line(_ label: String, _ id: String, _ c: TextEditingController) -> Widget {
            Row(children: [
                SizedBox(width: 150, height: nil, child: Text(label)),
                SizedBox(width: 220, height: Chrome.touchFieldHeight, child: FluentTextBox(key: ValueKey(id), controller: c, placeholderText: "")),
            ])
        }
        var rows: [Widget] = [line("Chart title:", "charttitles-title", title)]
        if chart?.type.hasAxes ?? false {
            rows += [gap(8), line("Horizontal axis title:", "charttitles-cat", category),
                     gap(8), line("Vertical axis title:", "charttitles-val", value)]
        }
        return DialogShell(title: "Edit Titles", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                           okLabel: "OK", cancelLabel: "Cancel", width: 430,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
