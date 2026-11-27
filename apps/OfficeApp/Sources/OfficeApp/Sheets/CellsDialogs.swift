// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-RC-1: the Insert / Delete cells dialog (shift right/down, left/up, entire
// row or column) and the Row Height / Column Width / Default Width box.

import Flutter
import FlutterSwiftBridge

enum SizeKind {
    case rowHeight, columnWidth, defaultWidth
    /// Rows are in points; column widths in characters, as Excel asks.
    var unit: String { self == .rowHeight ? "points" : "characters" }
    var title: String { switch self { case .rowHeight: return "Row Height"; case .columnWidth: return "Column Width"; case .defaultWidth: return "Default Width" } }
}

enum CellsChoice: String { case shiftRight, shiftDown, shiftLeft, shiftUp, entireRow, entireColumn }

extension WorkbookController {
    /// Do what the Insert / Delete dialog chose, on the current selection.
    func applyCells(insert: Bool, _ choice: CellsChoice) {
        switch choice {
        case .entireRow: insert ? insertAtSelection(.rows) : deleteAtSelection(.rows)
        case .entireColumn: insert ? insertAtSelection(.cols) : deleteAtSelection(.cols)
        case .shiftRight: insertCells(selection, shift: .right)
        case .shiftDown: insertCells(selection, shift: .down)
        case .shiftLeft: deleteCells(selection, shift: .left)
        case .shiftUp: deleteCells(selection, shift: .up)
        }
    }

    /// Row height in points for the selection's rows (0 hides, as in Excel); one undo step.
    func setRowHeights(_ points: Double) {
        let r = selection
        structural { for row in r.top ... r.bottom { sheet.rowHeights[row] = max(0, points); sheet.fittedRows.remove(row); sheet.hiddenRows.remove(row) } }
    }

    /// Column width in points for the selection's columns; one undo step.
    func setColumnWidths(_ points: Double) {
        let r = selection
        structural { for col in r.left ... r.right { sheet.colWidths[col] = max(0, points); sheet.widenedCols.remove(col); sheet.hiddenCols.remove(col) } }
    }

    /// The sheet's standard column width in points (Format > Default Width); one undo step.
    func setDefaultColumnWidth(_ points: Double) {
        structural {
            sheet.defaultColWidthPt = max(1, points)
            sheet.defaultColWidthChars = Xlsx._pointsToChars(max(1, points), digit: sheet.digitWidth)
        }
    }
}

final class InsertDeleteCellsDialog: StatefulWidget {
    let insert: Bool
    let onApply: (CellsChoice) -> Void
    let onClose: () -> Void
    init(insert: Bool, onApply: @escaping (CellsChoice) -> Void, onClose: @escaping () -> Void) {
        self.insert = insert; self.onApply = onApply; self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { InsertDeleteCellsDialogState() }
}

final class InsertDeleteCellsDialogState: State<StatefulWidget> {
    private var _w: InsertDeleteCellsDialog { widget as! InsertDeleteCellsDialog }
    private(set) var choice: CellsChoice? = nil

    private var _current: CellsChoice { choice ?? (_w.insert ? .shiftRight : .shiftLeft) }

    override func build(_ context: BuildContext) -> Widget {
        let options: [(String, CellsChoice)] = _w.insert
            ? [("Shift cells right", .shiftRight), ("Shift cells down", .shiftDown), ("Entire row", .entireRow), ("Entire column", .entireColumn)]
            : [("Shift cells left", .shiftLeft), ("Shift cells up", .shiftUp), ("Entire row", .entireRow), ("Entire column", .entireColumn)]
        let page = Padding(padding: EdgeInsets(all: 8), child: Column(crossAxisAlignment: .stretch, children: options.map { name, c in
            SizedBox(key: ValueKey("cells-\(c.rawValue)"), width: nil, height: 28, child: FlatButton(
                child: Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0), child: Text(name)),
                checked: _current == c, width: nil, height: 28, alignLeft: true,
                action: { [weak self] in self?.setState { self?.choice = c } }))
        }))
        return DialogShell(
            title: _w.insert ? "Insert" : "Delete", page: page, width: 300,
            onOK: { [weak self] in
                guard let self else { return }
                self._w.onApply(self._current)
                self._w.onClose()
            },
            onCancel: { [weak self] in self?._w.onClose() })
    }
}

/// A one-number box in points: Row Height, Column Width, Default Width.
final class SizeDialog: StatefulWidget {
    let title: String
    let unit: String
    let start: Double
    let onApply: (Double) -> Void
    let onClose: () -> Void
    init(title: String, unit: String, start: Double, onApply: @escaping (Double) -> Void, onClose: @escaping () -> Void) {
        self.title = title; self.unit = unit; self.start = start; self.onApply = onApply; self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { SizeDialogState() }
}

final class SizeDialogState: State<StatefulWidget> {
    private var _w: SizeDialog { widget as! SizeDialog }
    private let _field = TextEditingController()
    var text: String { _field.text }

    override func initState() {
        super.initState()
        _field.text = Self.format((widget as! SizeDialog).start)
    }

    override func dispose() { _field.dispose(); super.dispose() }

    static func format(_ v: Double) -> String {
        let t = (v * 100).rounded() / 100
        return t == t.rounded() ? String(Int(t)) : String(t)
    }

    override func build(_ context: BuildContext) -> Widget {
        let page = Padding(padding: EdgeInsets(all: 8), child: Column(crossAxisAlignment: .stretch, children: [
            Text("\(_w.title) (\(_w.unit))"),
            SizedBox(key: ValueKey("size-input"), width: 120, height: Chrome.fieldHeight, child: FluentTextBox(controller: _field)),
        ]))
        return DialogShell(
            title: _w.title, page: page, width: 300,
            onOK: { [weak self] in
                guard let self else { return }
                if let v = Double(self.text.trimmingWhitespace()), v >= 0 { self._w.onApply(v) }
                self._w.onClose()
            },
            onCancel: { [weak self] in self?._w.onClose() })
    }
}
