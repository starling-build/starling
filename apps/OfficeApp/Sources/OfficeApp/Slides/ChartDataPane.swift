// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The chart's data, edited in a grid beside the slide (S6b) — what
// PowerPoint opens Excel for. Row 1 names the series, column A the
// categories (a scatter chart's x values); every cell is a field, and a
// change redraws the chart as it is typed. Typing in one cell is one undo
// step.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

final class ChartDataPane: StatefulWidget {
    let deck: DeckController
    let shape: SlideShape
    let onClose: () -> Void

    init(key: (any Key)? = nil, deck: DeckController, shape: SlideShape, onClose: @escaping () -> Void) {
        self.deck = deck
        self.shape = shape
        self.onClose = onClose
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> { ChartDataPaneState() }
}

final class ChartDataPaneState: State<StatefulWidget> {
    private var _w: ChartDataPane { widget as! ChartDataPane }
    /// One field per cell, keyed "row:column" (row -1 is the series names,
    /// column -1 the categories), plus "title".
    private var _fields: [String: TextEditingController] = [:]
    /// The chart as this pane last left it: anything else (an undo, the
    /// ribbon) reloads every field.
    private var _expected: Chart?

    override func dispose() {
        for c in _fields.values { c.dispose() }
        super.dispose()
    }

    private func _field(_ key: String, _ text: String) -> TextEditingController {
        if let c = _fields[key] { return c }
        let c = TextEditingController(text: text)
        _fields[key] = c
        return c
    }

    private static func _cell(_ chart: Chart, _ r: Int, _ c: Int) -> String {
        if r < 0 { return c < 0 ? "" : chart.series[c].name }
        if c < 0 { return chart.categories[r] }
        return (chart.series[c].values[safe: r] ?? nil).map(ChartXML.number) ?? ""
    }

    private func _commit(_ chart: Chart, key: String) {
        _expected = chart
        _w.deck.setChart(_w.shape, chart, coalesce: "\(_w.shape.id):\(key)")
    }

    private func _changed(_ r: Int, _ c: Int, _ text: String) {
        guard var chart = _w.shape.chart else { return }
        if r < 0 {
            guard c >= 0 else { return }
            chart.series[c].name = text
        } else if c < 0 {
            chart.categories[r] = text
        } else {
            let v = Double(text.trimmingCharacters(in: .whitespaces))
            while chart.series[c].values.count <= r { chart.series[c].values.append(nil) }
            chart.series[c].values[r] = v
        }
        _commit(chart, key: "\(r):\(c)")
    }

    /// Rows or series added or taken away: fields re-made from the data.
    private func _reshape(_ edit: (inout Chart) -> Void) {
        guard var chart = _w.shape.chart else { return }
        edit(&chart)
        for c in _fields.values { c.dispose() }
        _fields = [:]
        _expected = chart
        _w.deck.setChart(_w.shape, chart)
        setState {}
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        guard let chart = _w.shape.chart else { return SizedBox(width: 0, height: 0, child: nil) }
        if chart != _expected {
            for c in _fields.values { c.dispose() }
            _fields = [:]
            _expected = chart
        }
        let caption = fluent.typography.caption
        let cellW = 84.0, firstW = 104.0, rowH = 30.0
        let seriesCount = chart.type == .pie ? min(1, chart.series.count) : chart.series.count

        func cell(_ r: Int, _ c: Int) -> Widget {
            let key = "\(r):\(c)"
            return Padding(padding: EdgeInsets(left: 0, top: 0, right: 2, bottom: 2), child: SizedBox(
                width: c < 0 ? firstW : cellW, height: rowH,
                child: FluentTextBox(
                    controller: _field(key, Self._cell(chart, r, c)),
                    onChanged: { [weak self] text in self?._changed(r, c, text) },
                    readOnly: r < 0 && c < 0,
                    style: Flutter.TextStyle(fontSize: 12, fontWeight: r < 0 || c < 0 ? .w600 : .normal))))
        }
        var rows: [Widget] = []
        rows.append(Row(mainAxisSize: .min, children: [cell(-1, -1)] + (0 ..< seriesCount).map { cell(-1, $0) }))
        for r in chart.categories.indices {
            rows.append(Row(mainAxisSize: .min, children: [cell(r, -1)] + (0 ..< seriesCount).map { cell(r, $0) }))
        }

        let title = FluentTextBox(
            controller: _field("title", chart.title ?? ""),
            placeholderText: "No title",
            onChanged: { [weak self] text in
                guard let self, var chart = self._w.shape.chart else { return }
                chart.title = text.isEmpty ? nil : text
                self._commit(chart, key: "title")
            })

        let buttons = Wrap(spacing: 4, runSpacing: 4, children: [
            Button(onPressed: { [weak self] in
                self?._reshape { c in
                    c.categories.append(c.type == .scatter ? ChartXML.number(c.x(c.categories.count - 1) + 1) : "Category \(c.categories.count + 1)")
                    for i in c.series.indices { c.series[i].values.append(nil) }
                }
            }, child: Text("Add Row")),
            Button(onPressed: chart.categories.count > 1 ? { [weak self] in
                self?._reshape { c in
                    c.categories.removeLast()
                    for i in c.series.indices where !c.series[i].values.isEmpty { c.series[i].values.removeLast() }
                }
            } : nil, child: Text("Remove Row")),
            Button(onPressed: chart.type == .pie ? nil : { [weak self] in
                self?._reshape { c in
                    c.series.append(ChartSeries(name: "Series \(c.series.count + 1)",
                                                values: Array(repeating: nil, count: c.categories.count)))
                }
            }, child: Text("Add Series")),
            Button(onPressed: chart.series.count > 1 && chart.type != .pie ? { [weak self] in
                self?._reshape { c in c.series.removeLast() }
            } : nil, child: Text("Remove Series")),
        ])

        let header = Row(children: [
            Expanded(child: Text("Chart Data", style: fluent.typography.bodyStrong)),
            IconButton(icon: Icon(FluentSystemIcons.close, size: 14, color: fluent.resources.textFillColorPrimary),
                       onPressed: { [weak self] in self?._w.onClose() }),
        ])
        let body = Column(crossAxisAlignment: .start, children: [
            header,
            SizedBox(width: nil, height: 10, child: nil),
            Text("Title", style: caption),
            SizedBox(width: nil, height: 4, child: nil),
            SizedBox(width: nil, height: 30, child: title),
            SizedBox(width: nil, height: 14, child: nil),
            Text(chart.type == .scatter ? "X values down the first column, Y values beside them" : "Categories down, series across",
                 style: caption?.copyWith(color: fluent.resources.textFillColorSecondary)),
            SizedBox(width: nil, height: 6, child: nil),
            Column(mainAxisSize: .min, crossAxisAlignment: .start, children: rows),
            SizedBox(width: nil, height: 10, child: nil),
            buttons,
        ])
        // As wide as its columns (no sideways scrolling), never narrower
        // than the buttons need.
        let width = max(380, 24 + firstW + 2 + Double(seriesCount) * (cellW + 2) + 2)
        return SizedBox(width: width, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                      border: Border(left: BorderSide(color: fluent.resources.controlStrokeColorDefault, width: 1))),
            child: SingleChildScrollView(child: Padding(padding: EdgeInsets(all: 12), child: body))))
    }
}
