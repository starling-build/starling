// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CL-1: the Paste Special dialog, laid out as Excel's: what to paste in two columns, an operation,
// skip blanks, transpose, and Paste Link.

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

    /// Excel's Paste choices, its left column then its right.
    static let whats: [(String, PasteSpecial.What)] = [
        ("All", .all), ("Formulas", .formulas), ("Values", .values), ("Formats", .formats),
        ("Comments and Notes", .comments), ("Validation", .validation),
        ("All using Source theme", .allUsingSourceTheme), ("All except borders", .allExceptBorders),
        ("Column widths", .columnWidths), ("Formulas and number formats", .formulasAndNumberFormats),
        ("Values and number formats", .valuesAndNumberFormats), ("All merging conditional formats", .allMergingConditionalFormats),
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
        // Two columns, Excel's order: the first half of each list on the left.
        func columns(_ items: [Widget]) -> Widget {
            let half = (items.count + 1) / 2
            return Row(crossAxisAlignment: .start, children: [
                Expanded(child: Column(crossAxisAlignment: .stretch, children: Array(items[..<half]))),
                SizedBox(width: 8, height: nil),
                Expanded(child: Column(crossAxisAlignment: .stretch, children: Array(items[half...]))),
            ])
        }
        let whats = PasteSpecialDialog.whats.map { name, w in
            _choice("ps-what-\(name)", name, selected: how.what == w) { [weak self] in self?._set { $0.what = w } }
        }
        let ops = PasteSpecialDialog.operations.map { name, o in
            _choice("ps-op-\(name)", name, selected: how.operation == o) { [weak self] in self?._set { $0.operation = o } }
        }
        let page = Padding(padding: EdgeInsets(all: 8), child: Column(crossAxisAlignment: .stretch, children: [
            Text("Paste", style: fluent.typography.bodyStrong),
            columns(whats),
            SizedBox(width: nil, height: 6),
            Text("Operation", style: fluent.typography.bodyStrong),
            columns(ops),
            SizedBox(width: nil, height: 6),
            Row(children: [
                Expanded(child: Checkbox(key: ValueKey("ps-skip"), checked: how.skipBlanks,
                                         onChanged: { [weak self] v in self?._set { $0.skipBlanks = v ?? false } }, content: Text("Skip blanks"))),
                Expanded(child: Checkbox(key: ValueKey("ps-transpose"), checked: how.transpose,
                                         onChanged: { [weak self] v in self?._set { $0.transpose = v ?? false } }, content: Text("Transpose"))),
            ]),
            SizedBox(width: nil, height: 6),
            Text(PasteSpecialDialog.note(), style: fluent.typography.caption),
        ]))
        let shell = DialogShell(
            title: "Paste Special", page: page, width: 520,
            onOK: { [weak self] in
                guard let self else { return }
                self._w.onApply(self.how)
                self._w.onClose()
            },
            onCancel: { [weak self] in self?._w.onClose() })
        // Paste Link: each pasted cell refers to its copied one (Excel greys it for the choices it cannot link).
        // It stays in its place, greyed when it cannot link, so OK and Cancel never move.
        shell.middle = ("Paste Link", { [weak self] in
            guard let self else { return }
            var link = PasteSpecial(); link.link = true
            self._w.onApply(link)
            self._w.onClose()
        })
        shell.middleEnabled = (how.what == .all || how.what == .allExceptBorders) && how.operation == .none && !how.skipBlanks && !how.transpose
        return shell
    }
}

extension PasteSpecialDialog {
    /// Said when the clipboard did not come from this workbook.
    static func note() -> String { "Text copied from another app is pasted as values only." }
}
