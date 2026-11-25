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

    private var _open: String?      // the row whose colour panel is showing
    private var _more: (id: String, target: WorkbookController.ChartColorTarget)?
    private var _recent = RecentColors()

    private func _choose(_ t: WorkbookController.ChartColorTarget, _ choice: ColorChoice) {
        if let rgb = choice.resolved(theme: ColorMath.officeTheme) { _recent.use(rgb) }
        _ = _w.controller.setChartColor(_w.index, series: t.series, point: t.point, choice: choice)
        setState { self._open = nil; self._more = nil }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let targets = _w.controller.chartColorTargets(_w.index)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        func row(_ t: WorkbookController.ChartColorTarget, _ id: String) -> Widget {
            let now: Widget = t.color.map { Chrome.swatch($0, fluent) } ?? Text(t.themed ? "Theme colour" : "Automatic", style: fluent.typography.caption)
            var parts: [Widget] = [Row(children: [
                SizedBox(width: 200, height: nil, child: Text(t.title)),
                SizedBox(width: 90, height: nil, child: now),
                Chrome.textToggle("Colour", _open == id, fluent) { [weak self] in
                    self?.setState { self?._open = self?._open == id ? nil : id } },
            ])]
            if _open == id {
                parts.append(ColorPicker(recent: _recent.list, automaticLabel: "Automatic", noneLabel: nil,
                                         onChoose: { [weak self] c in self?._choose(t, c) },
                                         onMore: { [weak self] in self?.setState { self?._more = (id, t) } }))
            }
            return Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: parts)
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
        let dialog = DialogShell(title: "Format Data Series", page: SizedBox(width: nil, height: 360, child: SingleChildScrollView(child: Column(
                               mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows))),
                           okLabel: "Close", cancelLabel: "Close", width: 460,
                           onOK: _w.onClose, onCancel: _w.onClose)
        guard let m = _more else { return dialog }
        return Stack(children: [
            dialog,
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: CustomColorDialog(
                initial: UInt32(truncatingIfNeeded: m.target.color?.value ?? 0) & 0xFFFFFF,
                onOK: { [weak self] rgb in self?._choose(m.target, .rgb(rgb)) },
                onCancel: { [weak self] in self?.setState { self?._more = nil } })),
        ])
    }
}