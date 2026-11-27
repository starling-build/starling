// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-2: the custom filter dialog, opened from a filter dropdown's Number Filters…, Text
// Filters…, Date Filters… and Filter by Colour…. It sets one rule on the column through
// the controller's setFilterRule (one undo step): a comparison with an optional second
// condition (And or Or), the top or bottom N, above or below average, a date period, or a
// cell or font colour. "Clear" takes the column's filter off.

import Flutter
import FlutterSwiftBridge
import Foundation

final class FilterDialog: StatefulWidget {
    let controller: WorkbookController
    let col: Int
    let kind: String      // Number, Text, Date or Colour
    let onClose: () -> Void

    init(controller: WorkbookController, col: Int, kind: String, onClose: @escaping () -> Void) {
        self.controller = controller
        self.col = col
        self.kind = kind
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { FilterDialogState() }
}

final class FilterDialogState: State<StatefulWidget> {
    private var _w: FilterDialog { widget as! FilterDialog }

    static let numberOps: [(String, String)] = [
        ("equals", "equal"), ("does not equal", "notEqual"), ("is greater than", "greaterThan"),
        ("is greater than or equal to", "greaterThanOrEqual"), ("is less than", "lessThan"), ("is less than or equal to", "lessThanOrEqual")]
    static let textOps: [(String, String)] = [
        ("equals", "equal"), ("does not equal", "notEqual"), ("begins with", "beginsWith"), ("ends with", "endsWith"),
        ("contains", "contains"), ("does not contain", "notContains")]
    static let periods: [(String, String)] = FilterRule.periods.map { p in
        var out = ""
        for ch in p { if ch.isUppercase { out += " " + ch.lowercased() } else { out.append(ch) } }
        return (out.prefix(1).uppercased() + out.dropFirst(), p)
    }

    /// The choices in the first combo for this kind of filter.
    var modes: [(String, String)] {
        switch _w.kind {
        case "Number": return [("Comparison", "compare"), ("Top or bottom", "top"), ("Above average", "above"), ("Below average", "below")]
        case "Text": return [("Comparison", "compare")]
        case "Date": return [("Date period", "period")]
        default: return [("Cell colour", "fill"), ("Font colour", "font")]
        }
    }
    var ops: [(String, String)] { _w.kind == "Text" ? Self.textOps : Self.numberOps }

    private(set) var mode = "compare"
    private(set) var op1 = "equal"
    private(set) var op2 = ""
    private(set) var join = "and"
    private(set) var topSide = "top"
    private(set) var unit = "items"
    private(set) var period = "today"
    private(set) var color: UInt32?
    private(set) var message = ""
    private let _v1 = TextEditingController()
    private let _v2 = TextEditingController()
    private let _count = TextEditingController()

    override func initState() {
        super.initState()
        mode = modes[0].1
        _count.text = "10"
        if mode == "fill" { color = _w.controller.filterColors(col: _w.col, fill: true).first }
    }

    override func dispose() {
        _v1.dispose(); _v2.dispose(); _count.dispose()
        super.dispose()
    }

    func setMode(_ v: String) {
        mode = v
        if v == "fill" || v == "font" { color = _w.controller.filterColors(col: _w.col, fill: v == "fill").first }
        message = ""
        setState {}
    }
    func setOp1(_ v: String) { op1 = v; setState {} }
    func setOp2(_ v: String) { op2 = v; setState {} }
    func setJoin(_ v: String) { join = v; setState {} }
    func setTopSide(_ v: String) { topSide = v; setState {} }
    func setUnit(_ v: String) { unit = v; setState {} }
    func setPeriod(_ v: String) { period = v; setState {} }
    func setColor(_ v: UInt32) { color = v; setState {} }

    /// A text operator as the file writes it: equal or notEqual with wildcards.
    private static func condition(_ op: String, _ value: String) -> FilterCondition {
        switch op {
        case "beginsWith": return FilterCondition(op: "equal", value: value + "*")
        case "endsWith": return FilterCondition(op: "equal", value: "*" + value)
        case "contains": return FilterCondition(op: "equal", value: "*" + value + "*")
        case "notContains": return FilterCondition(op: "notEqual", value: "*" + value + "*")
        default: return FilterCondition(op: op, value: value)
        }
    }

    func clear() {
        _w.controller.setFilterRule(col: _w.col, nil)
        _w.controller.setFilter(col: _w.col, allowed: nil)
        _w.onClose()
    }

    func apply() {
        let rule: FilterRule
        switch mode {
        case "top":
            guard let n = Int(_count.text), n > 0 else { message = FilterProblem.badCount.message; setState {}; return }
            rule = .top(top: topSide == "top", percent: unit == "percent", count: n)
        case "above": rule = .average(above: true)
        case "below": rule = .average(above: false)
        case "period": rule = .period(period)
        case "fill", "font":
            guard let color else { message = FilterProblem.noColor.message; setState {}; return }
            rule = .color(fill: mode == "fill", color)
        default:
            let second = op2.isEmpty ? nil : Self.condition(op2, _v2.text)
            rule = .compare(Self.condition(op1, _v1.text), and: join == "and", second)
            if _v1.text.isEmpty { message = FilterProblem.needsValue.message; setState {}; return }
            if second != nil && _v2.text.isEmpty { message = FilterProblem.needsValue.message; setState {}; return }
        }
        if let p = _w.controller.setFilterRule(col: _w.col, rule) { message = p.message; setState {} }
        else { _w.onClose() }
    }

    private func _label(_ s: String, _ fluent: FluentThemeData) -> Widget { Text(s, style: fluent.typography.caption) }
    private func _gap(_ h: Double = 8) -> Widget { SizedBox(width: nil, height: h, child: nil) }
    private func _field(_ id: String, _ c: TextEditingController) -> Widget {
        SizedBox(width: nil, height: Chrome.fieldHeight, child: FluentTextBox(
            key: ValueKey(id), controller: c, placeholderText: "", onSubmitted: { [weak self] _ in self?.apply() }))
    }
    private func _combo(_ id: String, _ value: String, _ items: [(String, String)], _ set: @escaping (String) -> Void) -> Widget {
        SizedBox(width: 260, height: nil, child: ComboBox<String>(
            key: ValueKey(id), value: value,
            items: items.map { ComboBoxItem<String>(value: $0.1, child: Text($0.0)) },
            onChanged: { v in if let v { set(v) } }))
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let c = _w.controller
        let head = c.filterText(CellAddress(row: c.sheet.autoFilter?.range.top ?? 0, col: _w.col))
        var rows: [Widget] = [_label("Show rows where “\(head.isEmpty ? "Column " + CellAddress.columnName(_w.col) : head)”", fluent), _gap()]
        if modes.count > 1 { rows += [_combo("filter-mode", mode, modes) { [weak self] in self?.setMode($0) }, _gap()] }
        switch mode {
        case "top":
            rows += [_combo("filter-top-side", topSide, [("Top", "top"), ("Bottom", "bottom")]) { [weak self] in self?.setTopSide($0) }, _gap(6),
                     _field("filter-count", _count), _gap(6),
                     _combo("filter-unit", unit, [("Items", "items"), ("Percent", "percent")]) { [weak self] in self?.setUnit($0) }]
        case "period":
            rows += [_combo("filter-period", period, Self.periods.map { ($0.0, $0.1) }) { [weak self] in self?.setPeriod($0) }]
        case "fill", "font":
            let colors = c.filterColors(col: _w.col, fill: mode == "fill")
            rows += colors.isEmpty ? [_label("No colours in this column.", fluent)]
                : [_combo("filter-color", color.map { "#" + String($0, radix: 16, uppercase: true) } ?? "",
                          colors.map { ("#" + String($0, radix: 16, uppercase: true), "#" + String($0, radix: 16, uppercase: true)) }) { [weak self] v in
                    if let n = UInt32(v.dropFirst(), radix: 16) { self?.setColor(n) } }]
        case "compare":
            rows += [_combo("filter-op1", op1, ops) { [weak self] in self?.setOp1($0) }, _gap(6), _field("filter-value1", _v1), _gap(),
                     _combo("filter-join", join, [("And", "and"), ("Or", "or")]) { [weak self] in self?.setJoin($0) }, _gap(),
                     _combo("filter-op2", op2, [("(no second condition)", "")] + ops) { [weak self] in self?.setOp2($0) }]
            if !op2.isEmpty { rows += [_gap(6), _field("filter-value2", _v2)] }
            if _w.kind == "Text" { rows += [_gap(6), _label("? stands for any one character, * for any run.", fluent)] }
        default: break
        }
        rows += [_gap(), Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C))), _gap(6),
                 Row(children: [Button(key: ValueKey("filter-clear"), onPressed: { [weak self] in self?.clear() }, child: Text("Clear this filter"))])]
        return DialogShell(
            title: _w.kind == "Colour" ? "Filter by Colour" : "Custom AutoFilter",
            page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
            okLabel: "OK", cancelLabel: "Cancel", okEnabled: true, width: 380,
            onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
