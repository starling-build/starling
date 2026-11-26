// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Alt Text pane: the title and description a screen reader says for the selected picture, shape or chart (in Slides, Sheets
// and Writer). One multi-line box inside the shared DialogShell (Enter = OK, Esc = Cancel).

import Flutter
import OfficeText
import FlutterSwiftBridge

final class AltTextDialog: StatefulWidget {
    let initial: String
    let initialTitle: String
    let onApply: (String, String) -> Void
    let onCancel: () -> Void

    init(initial: String, title: String = "", onApply: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.initialTitle = title
        self.onApply = onApply
        self.onCancel = onCancel
        super.init()
    }

    override func createState() -> State<StatefulWidget> { AltTextDialogState() }
}

final class AltTextDialogState: State<StatefulWidget> {
    private var _w: AltTextDialog { widget as! AltTextDialog }
    private let _text = TextEditingController()
    private let _title = TextEditingController()

    override func initState() {
        super.initState()
        _text.text = _w.initial
        _title.text = _w.initialTitle
    }

    override func dispose() {
        _text.dispose()
        _title.dispose()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        let page = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
            Text("Title (a short name)", style: caption),
            SizedBox(width: nil, height: 4, child: nil),
            PKeyed("alt-title", SizedBox(width: nil, height: 32, child: FluentTextBox(controller: _title))),
            SizedBox(width: nil, height: 12, child: nil),
            Text("How would you describe this object and its context to someone who is blind?", style: caption),
            SizedBox(width: nil, height: 4, child: nil),
            PKeyed("alt-text", SizedBox(width: nil, height: 96, child: FluentTextBox(controller: _text, maxLines: 4))),
        ])
        return DialogShell(title: "Alt Text", page: page, width: 400,
                           onOK: { [weak self] in guard let self else { return }; self._w.onApply(self._text.text, self._title.text) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
