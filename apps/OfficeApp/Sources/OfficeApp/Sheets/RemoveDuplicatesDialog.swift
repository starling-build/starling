// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-6a: Data → Remove Duplicates. One checkbox per column (all ticked), "My data has headers", OK.
// The outcome ("2 duplicate values found and removed; 5 unique values remain.") goes to the status bar.

import Flutter
import FlutterSwiftBridge
import Foundation

final class RemoveDuplicatesDialog: StatefulWidget {
    let controller: WorkbookController
    let range: CellRange
    let hasHeader: Bool
    let onClose: () -> Void

    init(controller: WorkbookController, range: CellRange, hasHeader: Bool, onClose: @escaping () -> Void) {
        self.controller = controller
        self.range = range
        self.hasHeader = hasHeader
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { RemoveDuplicatesDialogState() }
}

final class RemoveDuplicatesDialogState: State<StatefulWidget> {
    private var _w: RemoveDuplicatesDialog { widget as! RemoveDuplicatesDialog }
    private(set) var hasHeader = false
    private(set) var chosen = Set<Int>()
    private(set) var message = ""

    override func initState() {
        super.initState()
        hasHeader = _w.hasHeader
        chosen = Set(_w.range.left ... _w.range.right)
    }

    func columnLabel(_ col: Int) -> String {
        if hasHeader {
            let text = _w.controller.input(CellAddress(row: _w.range.top, col: col))
            if !text.isEmpty { return text }
        }
        return "Column " + CellAddress.columnName(col)
    }

    func setHeader(_ on: Bool) { hasHeader = on; message = ""; setState {} }
    func setChosen(_ col: Int, _ on: Bool) { if on { chosen.insert(col) } else { chosen.remove(col) }; message = ""; setState {} }
    func selectAll(_ on: Bool) { chosen = on ? Set(_w.range.left ... _w.range.right) : []; message = ""; setState {} }

    func apply() {
        let c = _w.controller
        let out = c.removeDuplicates(_w.range, columns: chosen.sorted(), hasHeader: hasHeader)
        if let p = out.problem { message = p.message; setState {}; return }
        if let r = out.result { c.onCommand?(.status(r.message)) }
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        var rows: [Widget] = [
            Text("To delete duplicate values, select one or more columns that contain duplicates.", style: fluent.typography.body),
            gap(8),
            Row(children: [
                Button(key: ValueKey("dup-select-all"), onPressed: { [weak self] in self?.selectAll(true) }, child: Text("Select All")),
                SizedBox(width: 8, height: nil, child: nil),
                Button(key: ValueKey("dup-unselect-all"), onPressed: { [weak self] in self?.selectAll(false) }, child: Text("Unselect All")),
            ]),
            gap(6),
            Checkbox(key: ValueKey("dup-has-header"), checked: hasHeader, onChanged: { [weak self] v in self?.setHeader(v ?? false) },
                     content: Text("My data has headers")),
            gap(6),
        ]
        for col in _w.range.left ... _w.range.right {
            rows.append(Checkbox(key: ValueKey("dup-col-\(col)"), checked: chosen.contains(col),
                                 onChanged: { [weak self] v in self?.setChosen(col, v ?? false) }, content: Text(columnLabel(col))))
            rows.append(gap(2))
        }
        rows.append(Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C))))
        return DialogShell(title: "Remove Duplicates", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                           okLabel: "OK", cancelLabel: "Cancel", width: 420,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
