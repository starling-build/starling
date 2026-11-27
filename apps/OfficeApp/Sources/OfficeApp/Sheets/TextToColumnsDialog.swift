// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-6b: Data → Text to Columns. Separator checkboxes, "treat consecutive separators as one", and a
// text qualifier. OK splits the selected column; a problem shows in red and the dialog stays.

import Flutter
import FlutterSwiftBridge
import Foundation

final class TextToColumnsDialog: StatefulWidget {
    let controller: WorkbookController
    let range: CellRange
    let onClose: () -> Void

    init(controller: WorkbookController, range: CellRange, onClose: @escaping () -> Void) {
        self.controller = controller
        self.range = range
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { TextToColumnsDialogState() }
}

final class TextToColumnsDialogState: State<StatefulWidget> {
    private var _w: TextToColumnsDialog { widget as! TextToColumnsDialog }
    private(set) var options = TextSplitOptions()
    private let _other = TextEditingController()
    private(set) var message = ""

    func edit(_ change: (inout TextSplitOptions) -> Void) { change(&options); message = ""; setState {} }

    func apply() {
        let c = _w.controller
        options.other = _other.text.first
        let out = c.textToColumns(_w.range, options: options)
        if let p = out.problem { message = p.message; setState {}; return }
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        func box(_ id: String, _ label: String, _ on: Bool, _ set: @escaping (inout TextSplitOptions, Bool) -> Void) -> Widget {
            Checkbox(key: ValueKey(id), checked: on, onChanged: { [weak self] v in self?.edit { set(&$0, v ?? false) } }, content: Text(label))
        }
        let rows: [Widget] = [
            Text("Choose the separators your data contains.", style: fluent.typography.body),
            gap(8),
            box("ttc-tab", "Tab", options.tab) { $0.tab = $1 },
            box("ttc-semicolon", "Semicolon", options.semicolon) { $0.semicolon = $1 },
            box("ttc-comma", "Comma", options.comma) { $0.comma = $1 },
            box("ttc-space", "Space", options.space) { $0.space = $1 },
            gap(4),
            Row(children: [
                Text("Other:"),
                SizedBox(width: 8, height: nil, child: nil),
                SizedBox(width: 60, height: Chrome.touchFieldHeight, child: FluentTextBox(key: ValueKey("ttc-other"), controller: _other, placeholderText: "")),
            ]),
            gap(6),
            box("ttc-consecutive", "Treat consecutive separators as one", options.consecutiveAsOne) { $0.consecutiveAsOne = $1 },
            box("ttc-quote", "Text in double quotes stays together", options.qualifier != nil) { $0.qualifier = $1 ? "\"" : nil },
            gap(6),
            Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C))),
        ]
        return DialogShell(title: "Text to Columns", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                           okLabel: "OK", cancelLabel: "Cancel", width: 420,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
