// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-6c: Data → Subtotal. "At each change in", "Use function", "Add subtotal to", "Replace current
// subtotals", Remove All. Only what the app does is offered (the summary row is always below the data).

import Flutter
import FlutterSwiftBridge
import Foundation

final class SubtotalDialog: StatefulWidget {
    let controller: WorkbookController
    let range: CellRange
    let onClose: () -> Void

    init(controller: WorkbookController, range: CellRange, onClose: @escaping () -> Void) {
        self.controller = controller
        self.range = range
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { SubtotalDialogState() }
}

final class SubtotalDialogState: State<StatefulWidget> {
    private var _w: SubtotalDialog { widget as! SubtotalDialog }
    private(set) var groupBy = 0
    private(set) var function = SubtotalFunction.sum
    private(set) var chosen = Set<Int>()
    private(set) var replace = true
    private(set) var message = ""

    override func initState() {
        super.initState()
        groupBy = _w.range.left
        chosen = [_w.range.right]
    }

    func columnLabel(_ col: Int) -> String {
        let text = _w.controller.input(CellAddress(row: _w.range.top, col: col))
        return text.isEmpty ? "Column " + CellAddress.columnName(col) : text
    }

    func setGroup(_ c: Int) { groupBy = c; message = ""; setState {} }
    func setFunction(_ f: SubtotalFunction) { function = f; message = ""; setState {} }
    func setChosen(_ c: Int, _ on: Bool) { if on { chosen.insert(c) } else { chosen.remove(c) }; message = ""; setState {} }
    func setReplace(_ on: Bool) { replace = on; setState {} }

    func apply() {
        let c = _w.controller
        let out = c.addSubtotals(_w.range, groupBy: groupBy, function: function, columns: chosen.sorted(), replace: replace)
        if let p = out.problem { message = p.message; setState {}; return }
        if let n = out.groups { c.onCommand?(.status("Subtotals added for \(n) group\(n == 1 ? "" : "s").")) }
        _w.onClose()
    }

    func removeAll() {
        let n = _w.controller.removeSubtotals(_w.range, groupBy: groupBy)
        if n == 0 { message = "There are no subtotals to remove."; setState {}; return }
        _w.controller.onCommand?(.status("Removed \(n) subtotal row\(n == 1 ? "" : "s")."))
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        let cols = Array(_w.range.left ... _w.range.right)
        var rows: [Widget] = [
            Text("At each change in:", style: fluent.typography.body),
            gap(4),
            SizedBox(width: 280, height: nil, child: ComboBox<Int>(
                key: ValueKey("sub-group"), value: groupBy,
                items: cols.map { ComboBoxItem<Int>(value: $0, child: Text(columnLabel($0))) },
                onChanged: { [weak self] v in if let v { self?.setGroup(v) } })),
            gap(8),
            Text("Use function:", style: fluent.typography.body),
            gap(4),
            SizedBox(width: 280, height: nil, child: ComboBox<Int>(
                key: ValueKey("sub-function"), value: function.rawValue,
                items: SubtotalFunction.allCases.map { ComboBoxItem<Int>(value: $0.rawValue, child: Text($0.label)) },
                onChanged: { [weak self] v in if let v, let f = SubtotalFunction(rawValue: v) { self?.setFunction(f) } })),
            gap(8),
            Text("Add subtotal to:", style: fluent.typography.body),
            gap(4),
        ]
        for c in cols {
            rows.append(Checkbox(key: ValueKey("sub-col-\(c)"), checked: chosen.contains(c),
                                 onChanged: { [weak self] v in self?.setChosen(c, v ?? false) }, content: Text(columnLabel(c))))
            rows.append(gap(2))
        }
        rows.append(gap(4))
        rows.append(Checkbox(key: ValueKey("sub-replace"), checked: replace, onChanged: { [weak self] v in self?.setReplace(v ?? false) },
                             content: Text("Replace current subtotals")))
        rows.append(gap(8))
        rows.append(Row(children: [Button(key: ValueKey("sub-remove-all"), onPressed: { [weak self] in self?.removeAll() }, child: Text("Remove All"))]))
        rows.append(gap(6))
        rows.append(Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C))))
        return DialogShell(title: "Subtotal", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                           okLabel: "OK", cancelLabel: "Cancel", width: 420,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
