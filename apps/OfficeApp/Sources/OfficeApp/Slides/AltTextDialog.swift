// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Picture Format → Alt Text (S-PI-1): the description a screen reader says for the
// selected picture. One multi-line box inside the shared DialogShell (Enter = OK, Esc = Cancel).

import Flutter
import OfficeText
import FlutterSwiftBridge

final class AltTextDialog: StatefulWidget {
    let initial: String
    let onApply: (String) -> Void
    let onCancel: () -> Void

    init(initial: String, onApply: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onApply = onApply
        self.onCancel = onCancel
        super.init()
    }

    override func createState() -> State<StatefulWidget> { AltTextDialogState() }
}

final class AltTextDialogState: State<StatefulWidget> {
    private var _w: AltTextDialog { widget as! AltTextDialog }
    private let _text = TextEditingController()

    override func initState() {
        super.initState()
        _text.text = _w.initial
    }

    override func dispose() {
        _text.dispose()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        let page = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
            Text("How would you describe this object and its context to someone who is blind?", style: caption),
            SizedBox(width: nil, height: 12, child: nil),
            SizedBox(width: nil, height: 96, child: FluentTextBox(controller: _text, maxLines: 4)),
        ])
        return DialogShell(title: "Alt Text", page: page, width: 400,
                           onOK: { [weak self] in guard let self else { return }; self._w.onApply(self._text.text) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
