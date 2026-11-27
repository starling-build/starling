// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Data → What-If Analysis → Data Table: the Row input cell and Column input cell, over the selected block.

import Flutter
import FlutterSwiftBridge
import Foundation

extension DataTableProblem {
    var message: String {
        switch self {
        case .selectionTooSmall: return "Select the formulas and the input values together: at least two rows and two columns."
        case .needsInput: return "Enter a row input cell, a column input cell, or both."
        case .inputInsideTable: return "An input cell cannot be inside the table's results."
        case .sameInput: return "The row and column input cells must be different."
        case .inputHasNoPlace: return "That is not a cell reference."
        }
    }
}

final class DataTableDialog: StatefulWidget {
    let controller: WorkbookController
    let onClose: () -> Void
    init(controller: WorkbookController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { DataTableDialogState() }
}

final class DataTableDialogState: State<StatefulWidget> {
    private var _w: DataTableDialog { widget as! DataTableDialog }
    let rowInput = TextEditingController()
    let colInput = TextEditingController()
    private(set) var message = ""

    private func cell(_ t: String) -> CellAddress?? {
        let s = t.trimmingWhitespace().replacingAll("$", with: "").uppercased()
        if s.isEmpty { return .some(nil) }
        guard let a = CellAddress(s) else { return nil }
        return .some(a)
    }

    func apply() {
        guard let r = cell(rowInput.text), let c = cell(colInput.text) else { message = DataTableProblem.inputHasNoPlace.message; setState {}; return }
        if let p = _w.controller.dataTable(selection: _w.controller.selection, rowInput: r, colInput: c) { message = p.message; setState {}; return }
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func line(_ label: String, _ id: String, _ c: TextEditingController) -> Widget {
            Row(children: [
                SizedBox(width: 130, height: nil, child: Text(label)),
                SizedBox(width: 160, height: Chrome.touchFieldHeight, child: FluentTextBox(key: ValueKey(id), controller: c, placeholderText: "")),
            ])
        }
        let rows: [Widget] = [
            line("Row input cell:", "datatable-row", rowInput), SizedBox(width: nil, height: 8, child: nil),
            line("Column input cell:", "datatable-col", colInput), SizedBox(width: nil, height: 8, child: nil),
            Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C))),
        ]
        return DialogShell(title: "Data Table", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                           okLabel: "OK", cancelLabel: "Cancel", width: 400,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
