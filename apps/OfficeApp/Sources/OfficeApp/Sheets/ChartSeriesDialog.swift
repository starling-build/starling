// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CH-1e: Chart Design → Select Data. Each series' name, categories and values cells, typed as references; series can be added and removed.

import Flutter
import FlutterSwiftBridge
import Foundation

final class ChartSeriesDialog: StatefulWidget {
    let controller: WorkbookController
    let index: Int
    let onClose: () -> Void
    init(controller: WorkbookController, index: Int, onClose: @escaping () -> Void) {
        self.controller = controller
        self.index = index
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { ChartSeriesDialogState() }
}

final class ChartSeriesDialogState: State<StatefulWidget> {
    private var _w: ChartSeriesDialog { widget as! ChartSeriesDialog }
    private final class SeriesRow {
        let source: Int?
        let name = TextEditingController(), cat = TextEditingController(), val = TextEditingController()
        init(_ r: ChartSeriesRef) { source = r.source; name.text = r.name ?? ""; cat.text = r.cat ?? ""; val.text = r.val ?? "" }
    }
    private var _rows: [SeriesRow] = []
    private var _seeded = false
    private(set) var message = ""

    /// The list the boxes hold, or nil (with the message set) when a reference is not one.
    func list() -> [ChartSeriesRef]? {
        var out: [ChartSeriesRef] = []
        for (n, r) in _rows.enumerated() {
            func text(_ t: TextEditingController) -> String? { let s = t.text.trimmingWhitespace(); return s.isEmpty ? nil : s }
            for (what, t) in [("name", text(r.name)), ("categories", text(r.cat)), ("values", text(r.val))] {
                if let t, !_w.controller.isChartRef(t) { message = "Series \(n + 1): the \(what) are not a reference to cells (like Sheet1!$B$2:$B$9)."; return nil }
            }
            guard let v = text(r.val) else { message = "Series \(n + 1) needs its values."; return nil }
            out.append(ChartSeriesRef(source: r.source, name: text(r.name), cat: text(r.cat), val: v))
        }
        if out.isEmpty { message = "A chart needs at least one series."; return nil }
        return out
    }

    func apply() {
        guard let l = list() else { setState {}; return }
        _w.controller.setChartSeries(_w.index, l)
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        if !_seeded {
            _seeded = true
            _rows = (_w.controller.chartSeries(_w.index) ?? []).map(SeriesRow.init)
        }
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        func box(_ id: String, _ c: TextEditingController, _ w: Double) -> Widget {
            SizedBox(width: w, height: nil, child: FluentTextBox(key: ValueKey(id), controller: c, placeholderText: ""))
        }
        var rows: [Widget] = [
            Row(children: [SizedBox(width: 120, height: nil, child: Text("Name")), SizedBox(width: 8, height: nil, child: nil),
                           SizedBox(width: 170, height: nil, child: Text("Categories")), SizedBox(width: 8, height: nil, child: nil),
                           SizedBox(width: 170, height: nil, child: Text("Values"))]),
            gap(4),
        ]
        for (n, r) in _rows.enumerated() {
            rows.append(Row(children: [
                box("chartseries-name-\(n)", r.name, 120), SizedBox(width: 8, height: nil, child: nil),
                box("chartseries-cat-\(n)", r.cat, 170), SizedBox(width: 8, height: nil, child: nil),
                box("chartseries-val-\(n)", r.val, 170), SizedBox(width: 8, height: nil, child: nil),
                SizedBox(key: ValueKey("chartseries-remove-\(n)"), width: 70, height: 28, child: FlatButton(
                    child: Text("Remove"), checked: false, width: 70, height: 28, alignLeft: false,
                    action: { [weak self] in self?.setState { self?._rows.remove(at: n) } })),
            ]))
            rows.append(gap(6))
        }
        rows.append(SizedBox(key: ValueKey("chartseries-add"), width: 110, height: 28, child: FlatButton(
            child: Text("Add series"), checked: false, width: 110, height: 28, alignLeft: false,
            action: { [weak self] in
                guard let self else { return }
                // A new series reads the column right of the last one's values, over the same rows.
                self.setState { self._rows.append(SeriesRow(ChartSeriesRef(source: nil, name: nil, cat: self._rows.last?.cat.text, val: nil))) }
            })))
        if !message.isEmpty {
            rows += [gap(6), Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C)))]
        }
        return DialogShell(title: "Select Data", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                           okLabel: "OK", cancelLabel: "Cancel", width: 600,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
