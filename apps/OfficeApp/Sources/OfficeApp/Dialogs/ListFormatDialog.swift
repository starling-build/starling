// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-LI-1: "Define New Number Format" / "Define New Bullet". A number style, the text
// around the number (`%1` stands for the number) and a live preview. OK applies the
// format to the caret's list level as one undoable step (`setListFormat`).

import Flutter
import FlutterSwiftBridge
import OfficeText

private final class LKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}

final class ListFormatDialog: StatefulWidget {
    let bullet: Bool
    let initial: ListLevelFormat
    let onOK: (ListLevelFormat) -> Void
    let onCancel: () -> Void
    init(bullet: Bool, initial: ListLevelFormat, onOK: @escaping (ListLevelFormat) -> Void, onCancel: @escaping () -> Void) {
        self.bullet = bullet; self.initial = initial; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { ListFormatDialogState() }
}

final class ListFormatDialogState: State<StatefulWidget> {
    private var _w: ListFormatDialog { widget as! ListFormatDialog }
    private let _text = TextEditingController()
    private(set) var style = ListNumberFormat.decimal

    static let styles: [(id: String, title: String, format: ListNumberFormat)] = [
        ("decimal", "1, 2, 3", .decimal), ("lower-letter", "a, b, c", .lowerLetter), ("upper-letter", "A, B, C", .upperLetter),
        ("lower-roman", "i, ii, iii", .lowerRoman), ("upper-roman", "I, II, III", .upperRoman),
    ]

    override func initState() {
        super.initState()
        style = _w.bullet ? .bullet : (_w.initial.format == .bullet ? .decimal : _w.initial.format)
        _text.text = _w.bullet ? (_w.initial.format == .bullet ? _w.initial.text : "\u{2022}") : (_w.initial.format == .bullet ? "%1." : _w.initial.text)
    }

    /// The format being defined, or nil when it can't show a number (no `%1`) or a bullet glyph.
    var result: ListLevelFormat? {
        let t = _text.text
        if _w.bullet { return t.isEmpty ? nil : ListLevelFormat(text: t, format: .bullet) }
        return t.containsSubstring("%1") ? ListLevelFormat(text: t, format: style) : nil
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func row(_ label: String, _ items: [Widget]) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children:
                [SizedBox(width: 110, height: nil, child: Text(label))] + items))
        }
        var rows: [Widget] = []
        if !_w.bullet {
            rows.append(row("Number style", [Wrap(children: Self.styles.map { s in
                LKeyed("lf-style-\(s.id)", Chrome.textToggle(s.title, style == s.format, fluent) { [weak self] in self?.setState { self?.style = s.format } })
            })]))
        }
        rows.append(row(_w.bullet ? "Bullet" : "Number format", [SizedBox(width: 160, height: 30, child: LKeyed("lf-text", FluentTextBox(
            controller: _text, onChanged: { [weak self] _ in self?.setState {} },
            onSubmitted: { [weak self] _ in if let r = self?.result { self?._w.onOK(r) } })))]))
        rows.append(row("Preview", [LKeyed("lf-preview", Text(result.map { $0.sample(1) + "   " + $0.sample(2) + "   " + $0.sample(3) } ?? "—"))]))
        return DialogShell(title: _w.bullet ? "Define New Bullet" : "Define New Number Format",
                           page: Column(crossAxisAlignment: .start, children: rows),
                           okEnabled: result != nil, width: 440,
                           onOK: { [weak self] in if let r = self?.result { self?._w.onOK(r) } },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
