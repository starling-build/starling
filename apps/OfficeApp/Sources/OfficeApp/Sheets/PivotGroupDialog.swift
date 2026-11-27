// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Group (or ungroup) a field of a PivotTable: a number field by start, end and step; a date field by Years, Quarters or Months.

import Flutter
import FlutterSwiftBridge
import Foundation

extension WorkbookController {
    /// What grouping field `f` of the pivot under the active cell offers: its numbers' range, whether the column is dates, and the group it has now.
    func pivotGroupInfo(_ f: Int) -> (min: Double, max: Double, isDate: Bool, current: PivotGroup?)? {
        guard let st = pivotPaneState(), let s = sheetOfPivotSource(st.index), let src = PivotSource.read(s, book: book), f >= 0, f < src.headers.count else { return nil }
        let nums = src.rows.compactMap { $0[f].number }
        guard let lo = nums.min(), let hi = nums.max() else { return nil }
        var isDate = false
        if let ws = book.sheets.first(where: { $0.name == src.sheet }), src.ref.bottom > src.ref.top {
            let a = CellAddress(row: src.ref.top + 1, col: src.ref.left + f)
            if let c = ws.cells[a] { isDate = NumberFormat.isDateTime(book.style(c.style ?? ws.defaultStyle(at: a)).numberFormat) }
        }
        return (lo, hi, isDate, st.spec.groups[f])
    }

    private func sheetOfPivotSource(_ k: Int) -> String? { sheet.pivots.indices.contains(k) ? sheet.pivots[k].source : nil }

    /// Group field `f` of the pivot under the active cell (nil ungroups).
    func setPivotGroupHere(_ f: Int, _ g: PivotGroup?) -> PivotProblem? {
        guard let st = pivotPaneState() else { return .noSource }
        return setPivotGroup(sheet: sheet, pivot: st.index, field: f, group: g)
    }
}

final class PivotGroupDialog: StatefulWidget {
    let controller: WorkbookController
    let field: Int
    let onClose: () -> Void

    init(controller: WorkbookController, field: Int, onClose: @escaping () -> Void) {
        self.controller = controller; self.field = field; self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { PivotGroupDialogState() }
}

final class PivotGroupDialogState: State<StatefulWidget> {
    private var _w: PivotGroupDialog { widget as! PivotGroupDialog }
    let startBox = TextEditingController(), endBox = TextEditingController(), byBox = TextEditingController()
    private(set) var unit = PivotDateUnit.months
    private(set) var message = ""
    private var _seeded = false
    private var _isDate = false

    func setUnit(_ u: PivotDateUnit) { unit = u; setState {} }

    func apply() {
        var g: PivotGroup
        if _isDate { g = .dates(unit) } else {
            guard let a = Double(startBox.text.trimmingWhitespace()), let b = Double(endBox.text.trimmingWhitespace()), let c = Double(byBox.text.trimmingWhitespace()) else {
                message = "Start, end and step must be numbers."; setState {}; return
            }
            g = .numbers(start: a, end: b, by: c)
        }
        if let p = _w.controller.setPivotGroupHere(_w.field, g) { message = p.message; setState {}; return }
        _w.onClose()
    }

    func ungroup() {
        if let p = _w.controller.setPivotGroupHere(_w.field, nil) { message = p.message; setState {}; return }
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let info = _w.controller.pivotGroupInfo(_w.field)
        if !_seeded, let info {
            _seeded = true
            _isDate = info.isDate
            switch info.current {
            case .some(.dates(let u)): unit = u
            case .some(.numbers(let a, let b, let c)): startBox.text = PivotCalc.numText(a); endBox.text = PivotCalc.numText(b); byBox.text = PivotCalc.numText(c)
            case .none:
                startBox.text = PivotCalc.numText(info.min); endBox.text = PivotCalc.numText(info.max)
                byBox.text = PivotCalc.numText(max(1, ((info.max - info.min) / 10).rounded(.up)))
            }
        }
        let fluent = FluentTheme.of(context)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        func box(_ key: String, _ c: TextEditingController) -> Widget { SizedBox(width: 300, height: Chrome.touchFieldHeight, child: FluentTextBox(key: ValueKey(key), controller: c, placeholderText: "")) }
        var rows: [Widget] = []
        if info == nil {
            rows.append(Text("This field has no numbers or dates to group.", style: fluent.typography.body))
        } else if _isDate {
            rows += [Text("By:", style: fluent.typography.body), gap(4), SizedBox(width: 300, height: nil, child: ComboBox<String>(
                key: ValueKey("pvg-unit"), value: unit.rawValue,
                items: PivotDateUnit.allCases.map { ComboBoxItem<String>(value: $0.rawValue, child: Text($0.title)) },
                onChanged: { [weak self] v in if let v, let u = PivotDateUnit(rawValue: v) { self?.setUnit(u) } }))]
        } else {
            rows += [Text("Starting at:", style: fluent.typography.body), gap(4), box("pvg-start", startBox), gap(8),
                     Text("Ending at:", style: fluent.typography.body), gap(4), box("pvg-end", endBox), gap(8),
                     Text("By:", style: fluent.typography.body), gap(4), box("pvg-by", byBox)]
        }
        if info?.current != nil { rows += [gap(8), Button(key: ValueKey("pvg-ungroup"), onPressed: { [weak self] in self?.ungroup() }, child: Text("Ungroup"))] }
        rows += [gap(6), Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C)))]
        return DialogShell(title: "Grouping", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                           okLabel: "OK", cancelLabel: "Cancel", width: 380,
                           onOK: { [weak self] in if info == nil { self?._w.onClose() } else { self?.apply() } }, onCancel: _w.onClose)
    }
}
