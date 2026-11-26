// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-TB-1: the Insert Table grid. Ten columns by eight rows of squares; the squares under the pointer light up
// and a caption above reads "3 × 4 Table" (columns × rows, as Word's reads). A click inserts that table.

import Flutter
import FlutterSwiftBridge

/// A menu entry holding the size grid.
final class TableGridMenuItem: MenuFlyoutItemBase {
    static let columns = 10
    static let rows = 8
    let onChoose: (_ rows: Int, _ columns: Int) -> Void

    init(onChoose: @escaping (_ rows: Int, _ columns: Int) -> Void) {
        self.onChoose = onChoose
        super.init(key: ValueKey("table-grid"))
    }

    override func buildItem(_ context: any BuildContext) -> Widget {
        let close: () -> Void = {
            if let scope = FlyoutScope.maybeOf(context) { scope.close() } else { Navigator.maybeOf(context)?.maybePop() }
        }
        return TableGridPicker(onChoose: { [onChoose] r, c in close(); onChoose(r, c) })
    }

    /// The caption for a hovered square (nothing hovered: "Insert Table").
    static func caption(rows: Int, columns: Int) -> String {
        rows > 0 && columns > 0 ? "\(columns) × \(rows) Table" : "Insert Table"
    }
}

final class TableGridPicker: StatefulWidget {
    let onChoose: (_ rows: Int, _ columns: Int) -> Void
    init(onChoose: @escaping (_ rows: Int, _ columns: Int) -> Void) {
        self.onChoose = onChoose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { TableGridPickerState() }
}

final class TableGridPickerState: State<StatefulWidget> {
    private var _w: TableGridPicker { widget as! TableGridPicker }
    private(set) var hotRows = 0
    private(set) var hotColumns = 0

    func hover(row: Int, column: Int) {
        setState { self.hotRows = row; self.hotColumns = column }
    }

    override func build(_ context: BuildContext) -> Widget {
        let cell = 18.0
        var rowWidgets: [Widget] = []
        for r in 1...TableGridMenuItem.rows {
            var squares: [Widget] = []
            for c in 1...TableGridMenuItem.columns {
                let lit = r <= hotRows && c <= hotColumns
                squares.append(MouseRegion(
                    onEnter: { [weak self] _ in self?.hover(row: r, column: c) },
                    child: GestureDetector(
                        key: ValueKey("table-grid-\(r)-\(c)"),
                        onTap: { [weak self] in self?._w.onChoose(r, c) },
                        behavior: .opaque,
                        child: Padding(padding: EdgeInsets(left: 1, top: 1, right: 1, bottom: 1), child: SizedBox(width: cell - 2, height: cell - 2, child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: lit ? Color(0xFFCDE6F7) : Color(0xFFFFFFFF),
                                border: Border.all(color: lit ? Color(0xFF2B79BD) : Color(0xFFBDBDBD), width: 1))))))))
            }
            rowWidgets.append(Row(mainAxisSize: .min) { squares })
        }
        return MouseRegion(
            onExit: { [weak self] _ in self?.hover(row: 0, column: 0) },
            child: Padding(padding: EdgeInsets(left: 8, top: 8, right: 8, bottom: 8), child: Column(mainAxisSize: .min, crossAxisAlignment: .start) {
                Text(TableGridMenuItem.caption(rows: hotRows, columns: hotColumns), key: ValueKey("table-grid-caption"))
                SizedBox(height: 6)
                Column(mainAxisSize: .min) { rowWidgets }
            }))
    }
}
