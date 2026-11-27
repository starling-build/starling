// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-FI-1: Home → Fill → Series. Series in rows or columns; Linear, Growth, Date (day, weekday, month,
// year) or AutoFill; a step value and an optional stop value. The model is one undoable step.

import Flutter
import FlutterSwiftBridge
import Foundation

enum SeriesType: Int, CaseIterable {
    case linear, growth, date, autoFill
    var label: String { ["Linear", "Growth", "Date", "AutoFill"][rawValue] }
}

enum SeriesDateUnit: Int, CaseIterable {
    case day, weekday, month, year
    var label: String { ["Day", "Weekday", "Month", "Year"][rawValue] }
}

struct SeriesOptions: Equatable {
    var byRows = false
    var type = SeriesType.linear
    var unit = SeriesDateUnit.day
    var step = 1.0
    var stop: Double? = nil
}

extension WorkbookController {
    /// What the dialog opens with: rows when the selection is wider than tall, as Excel guesses.
    var defaultSeriesOptions: SeriesOptions {
        var o = SeriesOptions()
        o.byRows = selection.cols > selection.rows
        return o
    }

    private static let _seriesCap = 10_000

    private static func _addMonths(_ serial: Double, _ months: Int) -> Double {
        let (y, m, d) = ExcelDate.ymd(serial)
        let total = y * 12 + (m - 1) + months
        let ny = Int((Double(total) / 12).rounded(.down)), nm = total - ny * 12 + 1
        let (ey, em) = nm == 12 ? (ny + 1, 1) : (ny, nm + 1)
        let dim = Int(ExcelDate.serial(ey, em, 1) - ExcelDate.serial(ny, nm, 1))
        return ExcelDate.serial(ny, nm, min(d, dim))
    }

    /// Fills each row (or column) of the selection after its first cell, or, for one cell, up to the stop
    /// value. Returns a message when nothing was filled, nil on success.
    @discardableResult
    func fillSeries(_ o: SeriesOptions) -> String? {
        let sel = selection
        let ws = sheet
        let along = o.byRows ? sel.cols : sel.rows
        let lines = o.byRows ? Array(sel.top ... sel.bottom) : Array(sel.left ... sel.right)
        if along < 2 && o.stop == nil { return "Select more than one cell, or enter a Stop value." }
        if !o.step.isFinite { return "The step value is not a number." }
        func at(_ line: Int, _ k: Int) -> CellAddress {
            o.byRows ? CellAddress(row: line, col: sel.left + k) : CellAddress(row: sel.top + k, col: line)
        }
        if o.type != .autoFill, along < 2, let stop = o.stop {
            let progresses = o.type == .growth ? (o.step > 1 && stop > 1) || (o.step < 1 && o.step > 0 && stop < 1) || o.step < 0 : o.step != 0
            if !progresses { return "That step never reaches the stop value." }
        }
        var before: [CellAddress: Cell?] = [:]
        var last = sel
        for line in lines {
            let first = at(line, 0)
            guard let seed = ws.cells[first] else { if o.type == .autoFill { continue }; return "The first cell of each \(o.byRows ? "row" : "column") must hold a number." }
            var values: [String] = []
            if o.type == .autoFill {
                let n = max(0, along - 1)
                guard let s = _series([seed], count: n, forward: true) else {
                    // Not a series: copies, as AutoFill does.
                    for k in 1 ..< max(1, along) {
                        let a = at(line, k)
                        if refusesEdit([a]) { return nil }
                        before[a] = .some(ws.cells[a]); ws.cells[a] = _copied(seed, from: first, to: a)
                    }
                    continue
                }
                values = s
            } else {
                guard let start = seed.value.number else { return "The first cell of each \(o.byRows ? "row" : "column") must hold a number." }
                let limit = along < 2 ? Self._seriesCap : along - 1
                var prev = start
                for k in 1 ... max(1, limit) {
                    var v: Double
                    switch o.type {
                    case .linear: v = start + o.step * Double(k)
                    case .growth: v = start * pow(o.step, Double(k))
                    default:
                        switch o.unit {
                        case .day: v = start + o.step * Double(k)
                        case .month: v = Self._addMonths(start, Int(o.step) * k)
                        case .year: v = Self._addMonths(start, 12 * Int(o.step) * k)
                        case .weekday:
                            v = prev
                            let dir = o.step < 0 ? -1.0 : 1.0
                            for _ in 0 ..< Int(abs(o.step)) {
                                repeat { v += dir } while [1, 7].contains(ExcelDate.weekday(v))
                            }
                            if o.step == 0 { v = prev }
                        }
                    }
                    if !v.isFinite { break }
                    if let stop = o.stop, (o.step >= 0 && !(o.type == .growth && o.step < 1) ? v > stop : v < stop) { break }
                    values.append(NumberFormat.full(v))
                    prev = v
                }
            }
            for (i, v) in values.enumerated() {
                let a = at(line, i + 1)
                if refusesEdit([a]) { return nil }
                before[a] = .some(ws.cells[a])
                var c = seed
                c.formula = nil; c.cached = nil; c.rawFormula = nil
                c.input = v
                if let parsed = InputParser.parse(v) { c.value = parsed.value } else { c.value = .text(v) }
                ws.cells[a] = c
                last = last.union(CellRange(a, a))
            }
        }
        if before.isEmpty { return "Nothing to fill: the stop value is already passed." }
        _record(sheet: activeSheet, before: before)
        select(range: last, active: active)
        return nil
    }
}

final class SeriesDialog: StatefulWidget {
    let controller: WorkbookController
    let onClose: () -> Void
    init(controller: WorkbookController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { SeriesDialogState() }
}

final class SeriesDialogState: State<StatefulWidget> {
    private var _w: SeriesDialog { widget as! SeriesDialog }
    private(set) var options = SeriesOptions()
    let stepText = TextEditingController()
    let stopText = TextEditingController()
    private(set) var message = ""
    private var _seeded = false

    func setByRows(_ on: Bool) { options.byRows = on; setState {} }
    func setType(_ t: SeriesType) { options.type = t; setState {} }
    func setUnit(_ u: SeriesDateUnit) { options.unit = u; setState {} }

    func apply() {
        let st = stepText.text.trimmingWhitespace(), sp = stopText.text.trimmingWhitespace()
        guard let step = st.isEmpty ? 1.0 : Double(st) else { message = "The step value is not a number."; setState {}; return }
        var o = options
        o.step = step
        if sp.isEmpty { o.stop = nil } else if let v = Double(sp) { o.stop = v } else { message = "The stop value is not a number."; setState {}; return }
        if let p = _w.controller.fillSeries(o) { message = p; setState {}; return }
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        if !_seeded { _seeded = true; options = _w.controller.defaultSeriesOptions; stepText.text = "1" }
        let fluent = FluentTheme.of(context)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        var rows: [Widget] = [
            Text("Series in:", style: fluent.typography.body), gap(4),
            Row(children: [
                Checkbox(key: ValueKey("series-rows"), checked: options.byRows, onChanged: { [weak self] _ in self?.setByRows(true) }, content: Text("Rows")),
                SizedBox(width: 16, height: nil, child: nil),
                Checkbox(key: ValueKey("series-cols"), checked: !options.byRows, onChanged: { [weak self] _ in self?.setByRows(false) }, content: Text("Columns")),
            ]),
            gap(8), Text("Type:", style: fluent.typography.body), gap(4),
            SizedBox(width: 200, height: nil, child: ComboBox<Int>(
                key: ValueKey("series-type"), value: options.type.rawValue,
                items: SeriesType.allCases.map { ComboBoxItem<Int>(value: $0.rawValue, child: Text($0.label)) },
                onChanged: { [weak self] v in if let v, let t = SeriesType(rawValue: v) { self?.setType(t) } })),
        ]
        if options.type == .date {
            rows += [gap(8), Text("Date unit:", style: fluent.typography.body), gap(4),
                SizedBox(width: 200, height: nil, child: ComboBox<Int>(
                    key: ValueKey("series-unit"), value: options.unit.rawValue,
                    items: SeriesDateUnit.allCases.map { ComboBoxItem<Int>(value: $0.rawValue, child: Text($0.label)) },
                    onChanged: { [weak self] v in if let v, let u = SeriesDateUnit(rawValue: v) { self?.setUnit(u) } }))]
        }
        if options.type != .autoFill {
            rows += [gap(8), Text("Step value:", style: fluent.typography.body), gap(4),
                SizedBox(width: 200, height: Chrome.touchFieldHeight, child: FluentTextBox(key: ValueKey("series-step"), controller: stepText, placeholderText: "1")),
                gap(8), Text("Stop value:", style: fluent.typography.body), gap(4),
                SizedBox(width: 200, height: Chrome.touchFieldHeight, child: FluentTextBox(key: ValueKey("series-stop"), controller: stopText, placeholderText: ""))]
        }
        rows += [gap(6), Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C)))]
        return DialogShell(title: "Series", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                           okLabel: "OK", cancelLabel: "Cancel", width: 340,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
