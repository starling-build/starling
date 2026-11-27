// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-ST-1: "Create a Style from Selection" — asks for a name; OK makes the
// style from the caret's formatting and applies it (`createStyleFromSelection`).

import Flutter
import FlutterSwiftBridge
import OfficeText

private final class NSKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}

final class NewStyleDialog: StatefulWidget {
    let taken: (String) -> Bool
    let onOK: (String) -> Void
    let onCancel: () -> Void
    init(taken: @escaping (String) -> Bool, onOK: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.taken = taken; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { NewStyleDialogState() }
}

final class NewStyleDialogState: State<StatefulWidget> {
    private var _w: NewStyleDialog { widget as! NewStyleDialog }
    private let _text = TextEditingController()

    /// The typed name, or nil when empty or already a style.
    var name: String? {
        let n = _text.text.trimmingWhitespace()
        return n.isEmpty || _w.taken(n) ? nil : n
    }

    override func build(_ context: any BuildContext) -> Widget {
        DialogShell(title: "Create New Style from Formatting", page:
            Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 70, height: nil, child: Text("Name:")),
                SizedBox(width: 200, height: Chrome.fieldHeight, child: NSKeyed("ns-name", FluentTextBox(
                    controller: _text, onChanged: { [weak self] _ in self?.setState {} },
                    onSubmitted: { [weak self] _ in if let n = self?.name { self?._w.onOK(n) } }))),
            ]),
            okEnabled: name != nil, width: 340,
            onOK: { [weak self] in if let n = self?.name { self?._w.onOK(n) } },
            onCancel: { [weak self] in self?._w.onCancel() })
    }
}
