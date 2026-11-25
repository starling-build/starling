// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-TB-11: Table Layout > Sort. Up to three keys (column, text/number/date, ascending/descending) and whether the
// first row is a header that stays where it is.

import Flutter
import FlutterSwiftBridge
import OfficeText

struct SortTableValues: Equatable {
    /// Column 0 means the key is not used (only allowed for the second and third).
    var keys: [RichDocumentController.TableSortKey] = [
        .init(column: 1), .init(column: 0), .init(column: 0),
    ]
    var headerRow = true
    var columnCount = 1

    /// The keys in use, columns as 0-based indices.
    var used: [RichDocumentController.TableSortKey] {
        keys.filter { $0.column >= 1 && $0.column <= columnCount }.map {
            .init(column: $0.column - 1, kind: $0.kind, ascending: $0.ascending)
        }
    }
}

final class SortTableDialog: StatefulWidget {
    let initial: SortTableValues
    let onOK: (SortTableValues) -> Void
    let onCancel: () -> Void
    init(initial: SortTableValues, onOK: @escaping (SortTableValues) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { SortTableDialogState() }
}

final class SortTableDialogState: State<StatefulWidget> {
    private var _w: SortTableDialog { widget as! SortTableDialog }
    private(set) var v = SortTableValues()
    private let _cols = [TextEditingController(), TextEditingController(), TextEditingController()]

    override func initState() {
        super.initState()
        v = _w.initial
        for i in 0 ..< 3 { _cols[i].text = v.keys[i].column == 0 ? "" : String(v.keys[i].column) }
    }

    func commit() {
        for i in 0 ..< 3 {
            let t = _cols[i].text
            if t.isEmpty, i > 0 { v.keys[i].column = 0 }
            else if let n = InsertTableValues.clamp(t, v.columnCount) { v.keys[i].column = n }
            else if v.keys[i].column == 0, i == 0 { v.keys[i].column = 1 }
            _cols[i].text = v.keys[i].column == 0 ? "" : String(v.keys[i].column)
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func toggle(_ id: String, _ label: String, _ on: Bool, _ set: @escaping () -> Void) -> Widget {
            PKeyed(id, Chrome.textToggle(label, on, fluent, action: { [weak self] in self?.setState { set() } }))
        }
        func keyRow(_ i: Int) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 10), child: Column(crossAxisAlignment: .start, children: [
                Row(crossAxisAlignment: .center, children: [
                    SizedBox(width: 110, height: nil, child: Text(i == 0 ? "Sort by column" : "Then by column")),
                    PKeyed("sort-col-\(i)", SizedBox(width: 60, height: 30, child: FluentTextBox(
                        controller: _cols[i], onSubmitted: { [weak self] _ in self?.commit() },
                        onFocusChanged: { [weak self] f in if !f { self?.commit() } }))),
                ]),
                Row(crossAxisAlignment: .center, children: [
                    toggle("sort-text-\(i)", "Text", v.keys[i].kind == .text) { self.v.keys[i].kind = .text },
                    toggle("sort-num-\(i)", "Number", v.keys[i].kind == .number) { self.v.keys[i].kind = .number },
                    toggle("sort-date-\(i)", "Date", v.keys[i].kind == .date) { self.v.keys[i].kind = .date },
                    SizedBox(width: 16, height: nil, child: nil),
                    toggle("sort-asc-\(i)", "Ascending", v.keys[i].ascending) { self.v.keys[i].ascending = true },
                    toggle("sort-desc-\(i)", "Descending", !v.keys[i].ascending) { self.v.keys[i].ascending = false },
                ]),
            ]))
        }
        return DialogShell(title: "Sort", page: Column(crossAxisAlignment: .start, children: [
            keyRow(0), keyRow(1), keyRow(2),
            toggle("sort-header", "My list has a header row", v.headerRow) { self.v.headerRow.toggle() },
        ]), width: 520,
        onOK: { [weak self] in guard let self else { return }; self.commit(); self._w.onOK(self.v) },
        onCancel: { [weak self] in self?._w.onCancel() })
    }
}
