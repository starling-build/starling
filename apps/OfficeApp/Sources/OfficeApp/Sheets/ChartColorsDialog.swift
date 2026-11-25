// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CH-1f: Chart Design → Format Data Series. The colour of each series, and of each point of the first series on a bar, column, area or pie chart.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

final class ChartColorsDialog: StatefulWidget {
    let controller: WorkbookController
    let index: Int
    let onClose: () -> Void
    init(controller: WorkbookController, index: Int, onClose: @escaping () -> Void) {
        self.controller = controller
        self.index = index
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { ChartColorsDialogState() }
}

final class ChartColorsDialogState: State<StatefulWidget> {
    private var _w: ChartColorsDialog { widget as! ChartColorsDialog }

    static let palette: [(String, Color)] = [
        ("Black", Color(0xFF000000)), ("White", Color(0xFFFFFFFF)), ("Dark Gray", Color(0xFF595959)),
        ("Light Gray", Color(0xFFD9D9D9)), ("Dark Red", Color(0xFFC00000)), ("Red", Color(0xFFFF0000)),
        ("Orange", Color(0xFFFFC000)), ("Yellow", Color(0xFFFFFF00)), ("Light Green", Color(0xFF92D050)),
        ("Green", Color(0xFF00B050)), ("Light Blue", Color(0xFF00B0F0)), ("Blue", Color(0xFF0070C0)),
        ("Dark Blue", Color(0xFF002060)), ("Purple", Color(0xFF7030A0)),
    ]

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let targets = _w.controller.chartColorTargets(_w.index)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        func row(_ t: WorkbookController.ChartColorTarget, _ id: String) -> Widget {
            let now: Widget = t.color.map { Chrome.swatch($0, fluent) } ?? Text(t.themed ? "Theme colour" : "Automatic", style: fluent.typography.caption)
            return Row(children: [
                SizedBox(width: 200, height: nil, child: Text(t.title)),
                SizedBox(width: 90, height: nil, child: now),
                Chrome.colorMenu(FluentSystemIcons.paintBrush, "Colour", fluent, colors: Self.palette, none: "Automatic") { [weak self] c in
                    guard let self else { return }
                    _ = self._w.controller.setChartColor(self._w.index, series: t.series, point: t.point, color: c)
                    self.setState {}
                },
            ])
        }
        var rows: [Widget] = []
        if let targets {
            if !targets.series.isEmpty { rows.append(Text("Series")); rows.append(gap(4)) }
            for (n, t) in targets.series.enumerated() { rows.append(row(t, "chartcolor-series-\(n)")); rows.append(gap(4)) }
            if !targets.points.isEmpty {
                rows.append(gap(8)); rows.append(Text(targets.series.isEmpty ? "Slices" : "Points of the first series")); rows.append(gap(4))
                for (n, t) in targets.points.enumerated() { rows.append(row(t, "chartcolor-point-\(n)")); rows.append(gap(4)) }
            }
        } else { rows.append(Text("This chart's colours cannot be changed here.")) }
        return DialogShell(title: "Format Data Series", page: SizedBox(width: nil, height: 360, child: SingleChildScrollView(child: Column(
                               mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows))),
                           okLabel: "Close", cancelLabel: "Close", width: 460,
                           onOK: _w.onClose, onCancel: _w.onClose)
    }
}
