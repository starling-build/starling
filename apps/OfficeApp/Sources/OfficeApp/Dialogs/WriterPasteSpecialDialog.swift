// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-ED-1: Writer's Paste Special (Ctrl+Alt+V). The clipboard's source, then "As:" the formats it holds; OK pastes
// the chosen one alone.

import Flutter
import FlutterSwiftBridge
import OfficeText

final class WriterPasteSpecialDialog: StatefulWidget {
    let source: String
    let formats: [PasteSpecialFormat]
    let onOK: (PasteSpecialFormat) -> Void
    let onCancel: () -> Void
    init(source: String, formats: [PasteSpecialFormat], onOK: @escaping (PasteSpecialFormat) -> Void, onCancel: @escaping () -> Void) {
        self.source = source; self.formats = formats; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { WriterPasteSpecialDialogState() }

    /// The first words of the clipboard's text, as Word's "Source:" line shows it.
    static func sourceLine(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }
        let one = text.replacingAll("\r\n", with: " ").replacingAll("\n", with: " ")
        return one.count > 60 ? String(one.prefix(60)) + "…" : one
    }
}

final class WriterPasteSpecialDialogState: State<StatefulWidget> {
    private var _w: WriterPasteSpecialDialog { widget as! WriterPasteSpecialDialog }
    private(set) var chosen: PasteSpecialFormat?

    override func initState() {
        super.initState()
        chosen = _w.formats.first
    }

    override func build(_ context: BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        var rows: [Widget] = []
        if !_w.source.isEmpty {
            rows.append(Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8),
                                child: Text("Source: \(_w.source)", style: fluent.typography.body)))
        }
        rows.append(Text("As:", style: fluent.typography.bodyStrong))
        for f in _w.formats {
            rows.append(SizedBox(key: ValueKey("wps-\(f.label)"), width: nil, height: 28, child: FlatButton(
                child: Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0), child: Text(f.label)),
                checked: chosen == f, width: nil, height: 28, alignLeft: true,
                action: { [weak self] in self?.setState { self?.chosen = f } })))
        }
        if _w.formats.isEmpty { rows.append(Text("The clipboard holds nothing Writer can paste.", style: fluent.typography.caption)) }
        let page = Padding(padding: EdgeInsets(all: 8), child: Column(crossAxisAlignment: .stretch, children: rows))
        return DialogShell(title: "Paste Special", page: page, width: 380,
                           onOK: { [weak self] in
                               guard let self else { return }
                               if let f = self.chosen { self._w.onOK(f) } else { self._w.onCancel() }
                           },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
