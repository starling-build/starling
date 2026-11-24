// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Picture Format → Alt Text (S-PI-1): the description a screen reader says for the
// selected picture. A small modal sheet like Header & Footer: one multi-line box, OK / Cancel.

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
        let card = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
            Text("Alt Text", style: fluent.typography.subtitle),
            SizedBox(width: nil, height: 4, child: nil),
            Text("How would you describe this object and its context to someone who is blind?", style: caption),
            SizedBox(width: nil, height: 12, child: nil),
            SizedBox(width: 352, height: 96, child: FluentTextBox(controller: _text, maxLines: 4)),
            SizedBox(width: nil, height: 20, child: nil),
            Row(mainAxisAlignment: .end, children: [
                FilledButton(onPressed: { [weak self] in
                    guard let self else { return }
                    self._w.onApply(self._text.text)
                }, child: Text("OK")),
                SizedBox(width: 8, height: nil, child: nil),
                Button(onPressed: { [weak self] in self?._w.onCancel() }, child: Text("Cancel")),
            ]),
        ])
        return Stack(children: [
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Listener(
                behavior: .opaque,
                child: ColoredBox(color: Color(0x33000000), child: SizedBox(expand: ())))),
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Center(child: SizedBox(width: 400, height: nil, child: DecoratedBox(
                decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                          border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1),
                                          borderRadius: BorderRadius.circular(8),
                                          boxShadow: [BoxShadow(color: Color(0x40000000), offset: Offset(0, 8), blurRadius: 24)]),
                child: Padding(padding: EdgeInsets(all: 24), child: card))))),
        ])
    }
}
