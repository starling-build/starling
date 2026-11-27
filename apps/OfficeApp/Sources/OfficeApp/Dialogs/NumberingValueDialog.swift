// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-LI-1: "Set Numbering Value" — the number the current list item shows.
// OK applies it as one undoable step (`setNumberingValue`).

import Flutter
import FlutterSwiftBridge
import OfficeText

private final class NVKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}

final class NumberingValueDialog: StatefulWidget {
    let initial: Int
    let onOK: (Int) -> Void
    let onCancel: () -> Void
    init(initial: Int, onOK: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { NumberingValueDialogState() }
}

final class NumberingValueDialogState: State<StatefulWidget> {
    private var _w: NumberingValueDialog { widget as! NumberingValueDialog }
    private let _text = TextEditingController()

    override func initState() {
        super.initState()
        _text.text = String(_w.initial)
    }

    /// The typed value, or nil when it is not a whole number from 0 to 32767.
    var value: Int? {
        guard let n = Int(_text.text.trimmingWhitespace()), n >= 0, n <= 32767 else { return nil }
        return n
    }

    override func build(_ context: any BuildContext) -> Widget {
        DialogShell(title: "Set Numbering Value", page:
            Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 110, height: nil, child: Text("Set value to:")),
                SizedBox(width: 90, height: Chrome.fieldHeight, child: NVKeyed("nv-value", FluentTextBox(
                    controller: _text, onChanged: { [weak self] _ in self?.setState {} },
                    onSubmitted: { [weak self] _ in if let n = self?.value { self?._w.onOK(n) } }))),
            ]),
            okEnabled: value != nil, width: 300,
            onOK: { [weak self] in if let n = self?.value { self?._w.onOK(n) } },
            onCancel: { [weak self] in self?._w.onCancel() })
    }
}
