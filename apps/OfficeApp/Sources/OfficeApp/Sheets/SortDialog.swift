// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-1b: the Sort dialog (Data → Sort…). A list of levels, each a column and
// an order; "My data has headers" decides whether the first row stays put and
// names the columns. It opens on the region the quick Sort buttons would use,
// with the headers guess Excel makes. OK sorts through the controller's
// sortRange (one undo step); a refusal (merged cells, protected sheet) shows
// its message and the dialog stays.

import Flutter
import FlutterSwiftBridge
import Foundation

final class SortDialog: StatefulWidget {
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

    override func createState() -> State<StatefulWidget> { SortDialogState() }
}

final class SortDialogState: State<StatefulWidget> {
    private var _w: SortDialog { widget as! SortDialog }
    private(set) var hasHeader = false
    private(set) var levels: [SortKey] = []
    private(set) var message = ""

    override func initState() {
        super.initState()
        hasHeader = _w.hasHeader
        let c = _w.controller
        // Start on the active cell's column when it is inside the region, else the first column.
        let col = (_w.range.left ... _w.range.right).contains(c.active.col) ? c.active.col : _w.range.left
        levels = [SortKey(col: col, ascending: true)]
    }

    /// How a column is named in the list: its header text, or "Column B" without headers.
    func columnLabel(_ col: Int) -> String {
        let name = CellAddress.columnName(col)
        if hasHeader {
            let text = _w.controller.input(CellAddress(row: _w.range.top, col: col))
            if !text.isEmpty { return text }
        }
        return "Column " + name
    }

    func setHeader(_ on: Bool) { hasHeader = on; message = ""; setState {} }
    func setColumn(_ level: Int, _ col: Int) { levels[level].col = col; setState {} }
    func setAscending(_ level: Int, _ on: Bool) { levels[level].ascending = on; setState {} }

    func addLevel() {
        let used = Set(levels.map { $0.col })
        guard let col = (_w.range.left ... _w.range.right).first(where: { !used.contains($0) }) else {
            message = "Every column is already a level."; setState {}; return
        }
        levels.append(SortKey(col: col, ascending: true)); message = ""; setState {}
    }

    func removeLevel(_ i: Int) {
        guard levels.count > 1, levels.indices.contains(i) else { return }
        levels.remove(at: i); setState {}
    }

    func apply() {
        if let problem = _w.controller.sortRange(_w.range, keys: levels, hasHeader: hasHeader) {
            message = problem.message
            setState {}
        } else {
            _w.onClose()
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let cols = Array(_w.range.left ... _w.range.right)
        var rows: [Widget] = []
        for (i, level) in levels.enumerated() {
            rows.append(Padding(padding: EdgeInsets(left: 0, top: 4, right: 0, bottom: 4), child: Row(children: [
                SizedBox(width: 64, height: nil, child: Text(i == 0 ? "Sort by" : "Then by", style: fluent.typography.caption)),
                SizedBox(width: 170, height: nil, child: ComboBox<Int>(
                    key: ValueKey("sort-column-\(i)"), value: level.col,
                    items: cols.map { ComboBoxItem<Int>(value: $0, child: Text(columnLabel($0))) },
                    onChanged: { [weak self] v in if let v { self?.setColumn(i, v) } })),
                SizedBox(width: 8, height: nil, child: nil),
                SizedBox(width: 120, height: nil, child: ComboBox<Bool>(
                    key: ValueKey("sort-order-\(i)"), value: level.ascending,
                    items: [ComboBoxItem<Bool>(value: true, child: Text("A to Z")), ComboBoxItem<Bool>(value: false, child: Text("Z to A"))],
                    onChanged: { [weak self] v in if let v { self?.setAscending(i, v) } })),
                SizedBox(width: 8, height: nil, child: nil),
                Button(key: ValueKey("sort-remove-\(i)"), onPressed: levels.count > 1 ? { [weak self] in self?.removeLevel(i) } : nil, child: Text("Remove")),
            ])))
        }
        let page = Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: [
            Checkbox(key: ValueKey("sort-has-header"), checked: hasHeader, onChanged: { [weak self] v in self?.setHeader(v ?? false) },
                     content: Text("My data has headers")),
            SizedBox(width: nil, height: 8, child: nil),
        ] + rows + [
            SizedBox(width: nil, height: 6, child: nil),
            Row(children: [Button(key: ValueKey("sort-add-level"), onPressed: { [weak self] in self?.addLevel() }, child: Text("Add Level"))]),
            SizedBox(width: nil, height: 6, child: nil),
            Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C))),
        ])
        return DialogShell(title: "Sort", page: page, okLabel: "OK", cancelLabel: "Cancel", width: 520,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
