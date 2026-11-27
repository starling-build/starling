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
    /// Opens the Symbol picker; the picked character and font come back through the callback.
    let pickSymbol: ((@escaping (String, String?) -> Void) -> Void)?
    init(bullet: Bool, initial: ListLevelFormat, pickSymbol: ((@escaping (String, String?) -> Void) -> Void)? = nil,
         onOK: @escaping (ListLevelFormat) -> Void, onCancel: @escaping () -> Void) {
        self.bullet = bullet; self.initial = initial; self.onOK = onOK; self.onCancel = onCancel; self.pickSymbol = pickSymbol
        super.init()
    }
    override func createState() -> State<StatefulWidget> { ListFormatDialogState() }
}

final class ListFormatDialogState: State<StatefulWidget> {
    private var _w: ListFormatDialog { widget as! ListFormatDialog }
    private let _text = TextEditingController()
    private(set) var style = ListNumberFormat.decimal
    /// Word's own name for a style the editor counts in digits ("decimalZero": 01, 02, 03).
    private(set) var rawFormat: String? = nil
    /// The bullet's font (the Symbol picker's), nil for the text's own.
    private(set) var bulletFont: String? = nil

    static let styles: [(id: String, title: String, format: ListNumberFormat, raw: String?)] = [
        ("decimal", "1, 2, 3", .decimal, nil), ("decimal-zero", "01, 02, 03", .decimal, "decimalZero"),
        ("lower-letter", "a, b, c", .lowerLetter, nil), ("upper-letter", "A, B, C", .upperLetter, nil),
        ("lower-roman", "i, ii, iii", .lowerRoman, nil), ("upper-roman", "I, II, III", .upperRoman, nil),
    ]

    override func initState() {
        super.initState()
        style = _w.bullet ? .bullet : (_w.initial.format == .bullet ? .decimal : _w.initial.format)
        if !_w.bullet, _w.initial.format != .bullet, _w.initial.rawFormat == "decimalZero" { rawFormat = "decimalZero" }
        _text.text = _w.bullet ? (_w.initial.format == .bullet ? _w.initial.text : "\u{2022}") : (_w.initial.format == .bullet ? "%1." : _w.initial.text)
    }

    /// The format being defined, or nil when it can't show a number (no `%1`) or a bullet glyph.
    var result: ListLevelFormat? {
        let t = _text.text
        if _w.bullet {
            guard !t.isEmpty else { return nil }
            var f = ListLevelFormat(text: t, format: .bullet)
            if let font = bulletFont {
                f.numberRPrXML = "<w:rPr><w:rFonts w:ascii=\"\(font)\" w:hAnsi=\"\(font)\" w:hint=\"default\"/></w:rPr>"
            }
            return f
        }
        guard t.containsSubstring("%1") else { return nil }
        var f = ListLevelFormat(text: t, format: style)
        f.rawFormat = rawFormat
        return f
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func row(_ label: String, _ items: [Widget]) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children:
                [SizedBox(width: 110, height: nil, child: Text(label))] + items))
        }
        var rows: [Widget] = []
        if !_w.bullet {
            rows.append(row("Number style", [Expanded(child: Wrap(children: Self.styles.map { s in
                LKeyed("lf-style-\(s.id)", Chrome.textToggle(s.title, style == s.format && rawFormat == s.raw, fluent) { [weak self] in self?.setState { self?.style = s.format; self?.rawFormat = s.raw } })
            }))]))
        }
        rows.append(row(_w.bullet ? "Bullet" : "Number format", [SizedBox(width: 160, height: Chrome.fieldHeight, child: LKeyed("lf-text", FluentTextBox(
            controller: _text, onChanged: { [weak self] _ in self?.setState {} },
            onSubmitted: { [weak self] _ in if let r = self?.result { self?._w.onOK(r) } })))]))
        if _w.bullet, let pick = _w.pickSymbol {
            rows.append(row("Symbol", [LKeyed("lf-symbol", Chrome.textToggle("Symbol…" + (bulletFont.map { " (\($0))" } ?? ""), false, fluent) { [weak self] in
                pick { text, font in self?.setState { self?._text.text = text; self?.bulletFont = font } }
            })]))
        }
        rows.append(row("Preview", [LKeyed("lf-preview", Text(result.map { $0.sample(1) + "   " + $0.sample(2) + "   " + $0.sample(3) } ?? "—"))]))
        return DialogShell(title: _w.bullet ? "Define New Bullet" : "Define New Number Format",
                           page: Column(crossAxisAlignment: .start, children: rows),
                           okEnabled: result != nil, width: 440,
                           onOK: { [weak self] in if let r = self?.result { self?._w.onOK(r) } },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
