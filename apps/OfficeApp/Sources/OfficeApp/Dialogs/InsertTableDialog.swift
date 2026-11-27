// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-TB-1: Insert Table. A size the grid cannot reach (up to 63 columns, 200 rows)
// and how the columns size themselves. OK inserts the table as one undoable step.

import Flutter
import FlutterSwiftBridge
import OfficeText

struct InsertTableValues: Equatable {
    static let maxColumns = 63, maxRows = 200
    var columns = 5, rows = 2
    var fit: RichDocumentController.TableFit = .contents
    static func clamp(_ text: String, _ limit: Int) -> Int? {
        guard let n = Int(text.trimmingWhitespace()), n >= 1 else { return nil }
        return min(n, limit)
    }
}

final class InsertTableDialog: StatefulWidget {
    let onOK: (InsertTableValues) -> Void
    let onCancel: () -> Void
    init(onOK: @escaping (InsertTableValues) -> Void, onCancel: @escaping () -> Void) {
        self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { InsertTableDialogState() }
}

final class InsertTableDialogState: State<StatefulWidget> {
    private var _w: InsertTableDialog { widget as! InsertTableDialog }
    private(set) var v = InsertTableValues()
    private let _columns = TextEditingController()
    private let _rows = TextEditingController()

    override func initState() {
        super.initState()
        _columns.text = String(v.columns); _rows.text = String(v.rows)
    }

    /// Read both boxes back into `v`; a box that is not a number goes back to the last good value.
    func commit() {
        if let n = InsertTableValues.clamp(_columns.text, InsertTableValues.maxColumns) { v.columns = n }
        if let n = InsertTableValues.clamp(_rows.text, InsertTableValues.maxRows) { v.rows = n }
        _columns.text = String(v.columns); _rows.text = String(v.rows)
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func box(_ id: String, _ label: String, _ c: TextEditingController) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 130, height: nil, child: Text(label)),
                SizedBox(width: 70, height: Chrome.fieldHeight, child: FluentTextBox(
                    controller: c, onSubmitted: { [weak self] _ in self?.commit() },
                    onFocusChanged: { [weak self] f in if !f { self?.commit() } })),
            ]))
        }
        func choice(_ label: String, _ k: RichDocumentController.TableFit) -> Widget {
            Chrome.textToggle(label, v.fit == k, fluent) { [weak self] in self?.setState { self?.v.fit = k } }
        }
        let page = Column(crossAxisAlignment: .start, children: [
            box("it-columns", "Number of columns", _columns),
            box("it-rows", "Number of rows", _rows),
            Chrome.vgap(4),
            Text("AutoFit behaviour"), Chrome.vgap(4),
            Row(children: [choice("Fixed column width", .fixed), Chrome.gap(6),
                           choice("AutoFit to contents", .contents), Chrome.gap(6),
                           choice("AutoFit to window", .window)]),
        ])
        return DialogShell(title: "Insert Table", page: page, width: 480,
                           onOK: { [weak self] in guard let self else { return }; self.commit(); self._w.onOK(self.v) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
