// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Change Chart Type → Stock and Bubble: the dialog that asks for the data those forms need and the chart
// lacks (a stock's missing series, a bubble's sizes) rather than refusing.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

enum ChartFormKind: Equatable {
    case stock(ohlc: Bool)
    case bubble
}

final class ChartFormDialog: StatefulWidget {
    let controller: WorkbookController
    let kind: ChartFormKind
    let onClose: () -> Void
    init(controller: WorkbookController, kind: ChartFormKind, onClose: @escaping () -> Void) {
        self.controller = controller
        self.kind = kind
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { ChartFormDialogState() }
}

final class ChartFormDialogState: State<StatefulWidget> {
    private var _w: ChartFormDialog { widget as! ChartFormDialog }
    private var _fields: [TextEditingController] = []
    private var _problem: String?

    private var _roles: [String] {
        guard let i = _w.controller.selectedDrawing else { return [] }
        switch _w.kind {
        case .stock(let ohlc): return _w.controller.stockRolesMissing(i, ohlc: ohlc)
        case .bubble: return _w.controller.bubbleSizeRoles(i)
        }
    }

    private func _apply() {
        guard let i = _w.controller.selectedDrawing else { _w.onClose(); return }
        let texts = _fields.map { $0.text }
        let ok: Bool
        switch _w.kind {
        case .stock(let ohlc): ok = _w.controller.setChartVariant(i, .stock(ohlc: ohlc, extra: texts))
        case .bubble: ok = _w.controller.setChartVariant(i, .bubble(sizes: texts))
        }
        if ok { _w.onClose() } else { setState { self._problem = self._w.controller.chartNotice } }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        let roles = _roles
        while _fields.count < roles.count {
            let f = TextEditingController()
            if case .bubble = _w.kind, let i = _w.controller.selectedDrawing { f.text = _w.controller.suggestedBubbleSizes(i, series: _fields.count) }
            _fields.append(f)
        }
        var rows: [Widget] = []
        switch _w.kind {
        case .stock(let ohlc):
            rows.append(Text(ohlc ? "The series are used in this order: open, high, low, close."
                                  : "The series are used in this order: high, low, close."))
            rows.append(gap(6))
            if roles.isEmpty { rows.append(Text("The chart has all of them.")) }
            else { rows.append(Text("It lacks a series for each of these. Give the cells of its values:")) }
        case .bubble:
            rows.append(Text("A bubble chart sizes each bubble from a range of cells."))
            rows.append(gap(6))
            rows.append(Text("Give one range, or one for each series separated by commas, in the order of the series:"))
        }
        rows.append(gap(6))
        for (k, role) in roles.enumerated() {
            rows.append(Row(children: [
                SizedBox(width: 130, height: nil, child: Text(role + ":")),
                SizedBox(width: 260, height: Chrome.touchFieldHeight, child: FluentTextBox(key: ValueKey("chartform-\(k)"), controller: _fields[k], placeholderText: "Sheet1!$D$2:$D$6")),
            ]))
            rows.append(gap(6))
        }
        if let p = _problem { rows.append(Text(p, style: fluent.typography.caption)) }
        let title: String
        switch _w.kind {
        case .stock(let ohlc): title = ohlc ? "Stock Chart (Open-High-Low-Close)" : "Stock Chart (High-Low-Close)"
        case .bubble: title = "Bubble Chart"
        }
        return DialogShell(title: title, page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                           okLabel: "OK", cancelLabel: "Cancel", width: 480,
                           onOK: { [weak self] in self?._apply() }, onCancel: _w.onClose)
    }
}
