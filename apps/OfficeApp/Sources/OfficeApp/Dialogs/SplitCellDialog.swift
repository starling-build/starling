// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-TB-3: Split Cells. How many columns and rows the caret's cell becomes.

import Flutter
import FlutterSwiftBridge
import OfficeText

final class SplitCellDialog: StatefulWidget {
    let columns: Int, rows: Int
    let merge: Bool
    let onOK: (Int, Int, Bool) -> Void
    let onCancel: () -> Void
    init(columns: Int = 2, rows: Int = 1, merge: Bool = false, onOK: @escaping (Int, Int, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.columns = columns; self.rows = rows; self.merge = merge; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { SplitCellDialogState() }
}

final class SplitCellDialogState: State<StatefulWidget> {
    private var _w: SplitCellDialog { widget as! SplitCellDialog }
    private(set) var columns = 2, rows = 1
    /// "Merge cells before split": offered when several cells are selected, on as in Word.
    var merge = true
    private let _columns = TextEditingController()
    private let _rows = TextEditingController()

    override func initState() {
        super.initState()
        columns = _w.columns; rows = _w.rows
        _columns.text = String(columns); _rows.text = String(rows)
    }

    func commit() {
        if let n = InsertTableValues.clamp(_columns.text, InsertTableValues.maxColumns) { columns = n }
        if let n = InsertTableValues.clamp(_rows.text, InsertTableValues.maxRows) { rows = n }
        _columns.text = String(columns); _rows.text = String(rows)
    }

    override func build(_ context: any BuildContext) -> Widget {
        func box(_ label: String, _ c: TextEditingController) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 130, height: nil, child: Text(label)),
                SizedBox(width: 70, height: 30, child: FluentTextBox(
                    controller: c, onSubmitted: { [weak self] _ in self?.commit() },
                    onFocusChanged: { [weak self] f in if !f { self?.commit() } })),
            ]))
        }
        let fluent = FluentTheme.of(context)
        var rowsOfPage: [Widget] = [box("Number of columns", _columns), box("Number of rows", _rows)]
        if _w.merge {
            rowsOfPage.append(PKeyed("merge", Chrome.textToggle("Merge cells before split", merge, fluent) { [weak self] in
                self?.setState { if let s = self { s.merge.toggle() } }
            }))
        }
        let page = Column(crossAxisAlignment: .start, children: rowsOfPage)
        return DialogShell(title: "Split Cells", page: page, width: 400,
                           onOK: { [weak self] in guard let self else { return }; self.commit(); self._w.onOK(self.columns, self.rows, self._w.merge && self.merge) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
