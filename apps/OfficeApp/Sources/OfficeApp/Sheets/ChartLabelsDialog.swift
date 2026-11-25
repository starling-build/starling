// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CH-2: Chart Design → Add Chart Element → Data Labels. Show or hide, what the label says, and where it stands.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

final class ChartLabelsDialog: StatefulWidget {
    let controller: WorkbookController
    let index: Int
    let onClose: () -> Void
    init(controller: WorkbookController, index: Int, onClose: @escaping () -> Void) {
        self.controller = controller
        self.index = index
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { ChartLabelsDialogState() }
}

final class ChartLabelsDialogState: State<StatefulWidget> {
    private var _w: ChartLabelsDialog { widget as! ChartLabelsDialog }

    private func _apply(_ change: (inout ChartLabelEdit) -> Void) {
        guard let o = _w.controller.chartLabelOptions(_w.index) else { return }
        var e = o.edit
        change(&e)
        _ = _w.controller.setChartLabels(_w.index, e)
        setState {}
    }

    private static func positionName(_ p: String) -> String {
        switch p {
        case "outEnd": return "Outside End"
        case "inEnd": return "Inside End"
        case "ctr": return "Center"
        case "inBase": return "Inside Base"
        case "bestFit": return "Best Fit"
        case "t": return "Above"
        case "b": return "Below"
        case "l": return "Left"
        case "r": return "Right"
        default: return p
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        var rows: [Widget] = []
        if let o = _w.controller.chartLabelOptions(_w.index) {
            let e = o.edit
            func toggle(_ title: String, _ on: Bool, _ set: @escaping (inout ChartLabelEdit, Bool) -> Void) -> Widget {
                Chrome.textToggle(title, on, fluent) { [weak self] in self?._apply { set(&$0, !on) } }
            }
            rows.append(toggle("Show data labels", e.show) { $0.show = $1 })
            if e.show {
                rows.append(gap(8)); rows.append(Text("Label contains"))
                rows.append(toggle("Value", e.value) { $0.value = $1 })
                if o.canSeries { rows.append(toggle("Series name", e.series) { $0.series = $1 }) }
                if o.canCategory { rows.append(toggle("Category name", e.category) { $0.category = $1 }) }
                if o.canPercent { rows.append(toggle("Percentage", e.percent) { $0.percent = $1 }) }
                if !o.positions.isEmpty {
                    rows.append(gap(8)); rows.append(Text("Label position"))
                    rows.append(Chrome.textToggle("Automatic", e.position == nil, fluent) { [weak self] in self?._apply { $0.position = nil } })
                    for p in o.positions {
                        rows.append(Chrome.textToggle(Self.positionName(p), e.position == p, fluent) { [weak self] in self?._apply { $0.position = p } })
                    }
                }
            }
        } else { rows.append(Text("This chart's data labels cannot be changed here.")) }
        return DialogShell(title: "Data Labels", page: SizedBox(width: nil, height: 300, child: SingleChildScrollView(child: Column(
                               mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows))),
                           okLabel: "Close", cancelLabel: "Close", width: 380,
                           onOK: _w.onClose, onCancel: _w.onClose)
    }
}
