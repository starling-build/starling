// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CL-1: the Paste Special dialog. Picks what to paste, an operation, skip blanks, transpose.

import Flutter
import FlutterSwiftBridge

final class PasteSpecialDialog: StatefulWidget {
    let onApply: (PasteSpecial) -> Void
    let onClose: () -> Void
    init(onApply: @escaping (PasteSpecial) -> Void, onClose: @escaping () -> Void) {
        self.onApply = onApply; self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { PasteSpecialDialogState() }

    static let whats: [(String, PasteSpecial.What)] = [
        ("All", .all), ("Values", .values), ("Formulas", .formulas), ("Formats", .formats), ("Column widths", .columnWidths),
    ]
    static let operations: [(String, PasteSpecial.Operation)] = [
        ("None", .none), ("Add", .add), ("Subtract", .subtract), ("Multiply", .multiply), ("Divide", .divide),
    ]
}

final class PasteSpecialDialogState: State<StatefulWidget> {
    private var _w: PasteSpecialDialog { widget as! PasteSpecialDialog }
    private(set) var how = PasteSpecial()

    private func _set(_ change: (inout PasteSpecial) -> Void) { setState { change(&how) } }

    private func _choice(_ id: String, _ label: String, selected: Bool, _ action: @escaping () -> Void) -> Widget {
        SizedBox(key: ValueKey(id), width: nil, height: 28, child: FlatButton(
            child: Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0), child: Text(label)),
            checked: selected, width: nil, height: 28, alignLeft: true, action: action))
    }

    override func build(_ context: BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let page = Padding(padding: EdgeInsets(all: 8), child: Column(crossAxisAlignment: .stretch, children: [
            Text("Paste", style: fluent.typography.bodyStrong),
            Column(crossAxisAlignment: .stretch, children: PasteSpecialDialog.whats.map { name, w in
                _choice("ps-what-\(name)", name, selected: how.what == w) { [weak self] in self?._set { $0.what = w } }
            }),
            Text("Operation", style: fluent.typography.bodyStrong),
            Column(crossAxisAlignment: .stretch, children: PasteSpecialDialog.operations.map { name, o in
                _choice("ps-op-\(name)", name, selected: how.operation == o) { [weak self] in self?._set { $0.operation = o } }
            }),
            Checkbox(key: ValueKey("ps-skip"), checked: how.skipBlanks, onChanged: { [weak self] v in self?._set { $0.skipBlanks = v ?? false } }, content: Text("Skip blanks")),
            Checkbox(key: ValueKey("ps-transpose"), checked: how.transpose, onChanged: { [weak self] v in self?._set { $0.transpose = v ?? false } }, content: Text("Transpose")),
            Text(PasteSpecialDialog.note(), style: fluent.typography.caption),
        ]))
        return DialogShell(
            title: "Paste Special", page: page, width: 360,
            onOK: { [weak self] in
                guard let self else { return }
                self._w.onApply(self.how)
                self._w.onClose()
            },
            onCancel: { [weak self] in self?._w.onClose() })
    }
}

extension PasteSpecialDialog {
    /// Said when the clipboard did not come from this workbook.
    static func note() -> String { "Text copied from another app is pasted as values only." }
}
