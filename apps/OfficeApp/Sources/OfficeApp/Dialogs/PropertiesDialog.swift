// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-FD-1d: File → Info → Properties. Title, subject, author, keywords and comments; they are the file's own
// properties, and the AUTHOR, TITLE and SUBJECT fields read them.

import Flutter
import FlutterSwiftBridge
import OfficeText

final class PropertiesDialog: StatefulWidget {
    static let fields: [(key: String, label: String)] = [
        ("title", "Title"), ("subject", "Subject"), ("creator", "Author"), ("keywords", "Keywords"), ("description", "Comments"),
    ]
    let values: [String: String]
    let onOK: ([String: String]) -> Void
    let onCancel: () -> Void
    init(values: [String: String], onOK: @escaping ([String: String]) -> Void, onCancel: @escaping () -> Void) {
        self.values = values; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { PropertiesDialogState() }
}

final class PropertiesDialogState: State<StatefulWidget> {
    private var _w: PropertiesDialog { widget as! PropertiesDialog }
    private var _controllers: [String: TextEditingController] = [:]

    override func initState() {
        super.initState()
        for f in PropertiesDialog.fields {
            let c = TextEditingController()
            c.text = _w.values[f.key] ?? ""
            _controllers[f.key] = c
        }
    }

    override func dispose() {
        for c in _controllers.values { c.dispose() }
        super.dispose()
    }

    private func _ok() {
        var out: [String: String] = [:]
        for f in PropertiesDialog.fields { out[f.key] = _controllers[f.key]?.text ?? "" }
        _w.onOK(out)
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        var rows: [Widget] = []
        for (i, f) in PropertiesDialog.fields.enumerated() {
            if i > 0 { rows.append(SizedBox(width: nil, height: 10, child: nil)) }
            rows.append(Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 90, height: nil, child: Text(f.label, style: fluent.typography.body)),
                Expanded(child: SizedBox(width: nil, height: Chrome.fieldHeight, child: PKeyed("prop-\(f.key)", FluentTextBox(
                    controller: _controllers[f.key]!, onSubmitted: { [weak self] _ in self?._ok() }, autofocus: i == 0)))),
            ]))
        }
        return DialogShell(title: "Document Properties", page: Column(crossAxisAlignment: .stretch, children: rows), okEnabled: true, width: 420,
                           onOK: { [weak self] in self?._ok() }, onCancel: { [weak self] in self?._w.onCancel() })
    }
}
