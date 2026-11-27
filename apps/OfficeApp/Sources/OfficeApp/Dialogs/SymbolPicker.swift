// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The one Symbol picker (U-shared, W-ED-3), on DialogShell: pick a subset, click a character
// (or type its code), choose a font, Insert. It remembers the last 24 symbols used. Writer,
// Slides and Sheets each hand it a `SymbolHooks` saying what "insert" does in that app.

import Flutter
import FlutterSwiftBridge
import OfficeText

/// What the picker knows about characters, apart from any widget (so it is testable alone).
enum SymbolData {
    /// Named blocks of the Unicode chart, the ones people look for in a document.
    static let subsets: [(name: String, range: ClosedRange<UInt32>)] = [
        ("Basic Latin", 0x20 ... 0x7E), ("Latin-1 Supplement", 0xA0 ... 0xFF),
        ("Latin Extended-A", 0x100 ... 0x17F), ("Greek and Coptic", 0x370 ... 0x3FF),
        ("Cyrillic", 0x400 ... 0x4FF), ("General Punctuation", 0x2000 ... 0x206F),
        ("Currency Symbols", 0x20A0 ... 0x20CF), ("Letterlike Symbols", 0x2100 ... 0x214F),
        ("Number Forms", 0x2150 ... 0x218F), ("Arrows", 0x2190 ... 0x21FF),
        ("Mathematical Operators", 0x2200 ... 0x22FF), ("Box Drawing", 0x2500 ... 0x257F),
        ("Geometric Shapes", 0x25A0 ... 0x25FF), ("Miscellaneous Symbols", 0x2600 ... 0x26FF),
        ("Dingbats", 0x2700 ... 0x27BF),
    ]

    /// The characters of a subset that exist (no controls, no gaps).
    static func characters(in range: ClosedRange<UInt32>) -> [UInt32] {
        range.filter { v in
            guard let u = Unicode.Scalar(v) else { return false }
            switch u.properties.generalCategory {
            case .unassigned, .control, .surrogate, .privateUse, .format: return false
            default: return true
            }
        }
    }

    /// "20AC", "U+20ac", "0x20AC" -> 0x20AC; nil if it is not a real character.
    static func parseCode(_ text: String) -> UInt32? {
        var t = text.trimmingWhitespace().lowercased()
        for p in ["u+", "0x", "x"] where t.hasPrefix(p) { t = String(t.dropFirst(p.count)); break }
        guard !t.isEmpty, t.count <= 6, let v = UInt32(t, radix: 16), let u = Unicode.Scalar(v) else { return nil }
        if case .unassigned = u.properties.generalCategory { return nil }
        if case .control = u.properties.generalCategory { return nil }
        return v
    }

    static func code(_ v: UInt32) -> String {
        let h = String(v, radix: 16, uppercase: true)
        return "U+" + String(repeating: "0", count: max(0, 4 - h.count)) + h
    }

    static func name(_ v: UInt32) -> String {
        Unicode.Scalar(v)?.properties.name?.capitalized ?? ""
    }

    /// `recent` with `v` moved to the front, at most 24 long.
    static func remember(_ v: UInt32, in recent: [UInt32]) -> [UInt32] {
        Array(([v] + recent.filter { $0 != v }).prefix(24))
    }

    static func decodeRecent(_ s: String?) -> [UInt32] {
        (s ?? "").split(separator: " ").compactMap { UInt32($0, radix: 16) }
    }

    static func encodeRecent(_ r: [UInt32]) -> String {
        r.map { String($0, radix: 16) }.joined(separator: " ")
    }
}

struct SymbolHooks {
    /// The fonts offered; the first is "the current font" (nil font on insert).
    var fonts: [String]
    /// Insert the character, in `font` unless nil.
    var insert: (_ text: String, _ font: String?) -> Void
}

final class SymbolPicker: StatefulWidget {
    let hooks: SymbolHooks
    let onClose: () -> Void
    init(hooks: SymbolHooks, onClose: @escaping () -> Void) {
        self.hooks = hooks
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { SymbolPickerState() }
}

final class SymbolPickerState: State<StatefulWidget> {
    static let recentKey = "recent-symbols"
    private var _w: SymbolPicker { widget as! SymbolPicker }
    private let _code = TextEditingController()
    private(set) var subset = 1
    private(set) var fontIndex = 0
    private(set) var selected: UInt32? = nil
    private(set) var recent: [UInt32] = []
    private(set) var status = ""

    override func initState() {
        super.initState()
        recent = SymbolData.decodeRecent(OfficeSettings.string(Self.recentKey))
    }

    override func dispose() {
        _code.dispose()
        super.dispose()
    }

    func choose(_ v: UInt32) {
        setState {
            selected = v
            _code.text = String(v, radix: 16, uppercase: true)
            status = SymbolData.code(v) + "  " + SymbolData.name(v)
        }
    }

    func insertSelected() {
        // A code typed by hand wins over the last click.
        if let v = SymbolData.parseCode(_code.text) { selected = v }
        else if !_code.text.trimmingWhitespace().isEmpty { setState { status = "Not a character code" }; return }
        guard let v = selected, let u = Unicode.Scalar(v) else { setState { status = "Pick a symbol first" }; return }
        _w.hooks.insert(String(Character(u)), fontIndex == 0 ? nil : _w.hooks.fonts[fontIndex])
        recent = SymbolData.remember(v, in: recent)
        OfficeSettings.setString(Self.recentKey, SymbolData.encodeRecent(recent))
        setState { status = "Inserted " + SymbolData.code(v) }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let h = _w.hooks
        let face: String? = fontIndex == 0 ? nil : h.fonts[fontIndex]
        func cell(_ v: UInt32, _ key: String) -> Widget {
            let on = selected == v
            return PKeyed(key, SizedBox(width: 30, height: 30, child: Button(
                onPressed: { [weak self] in self?.choose(v) },
                child: Text(String(Character(Unicode.Scalar(v) ?? " ")),
                            style: fluent.typography.body?.copyWith(fontWeight: on ? .bold : nil, fontFamily: face)))))
        }
        func rows(_ list: [UInt32], prefix: String) -> [Widget] {
            stride(from: 0, to: list.count, by: 14).map { i in
                Row(children: list[i ..< min(i + 14, list.count)].map { cell($0, prefix + String($0, radix: 16, uppercase: true)) })
            }
        }
        let range = SymbolData.subsets[subset].range
        let page: [Widget] = [
            Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 70, height: nil, child: Text("Font", style: fluent.typography.body)),
                SizedBox(width: 190, height: nil, child: ComboBox<String>(
                    value: h.fonts[fontIndex],
                    items: h.fonts.map { ComboBoxItem<String>(value: $0, child: Text($0, style: fluent.typography.body)) },
                    onChanged: { [weak self] v in
                        guard let self, let v, let i = h.fonts.firstIndex(of: v) else { return }
                        self.setState { self.fontIndex = i }
                    })),
                SizedBox(width: 20, height: nil, child: nil),
                SizedBox(width: 70, height: nil, child: Text("Subset", style: fluent.typography.body)),
                SizedBox(width: 190, height: nil, child: ComboBox<String>(
                    value: SymbolData.subsets[subset].name,
                    items: SymbolData.subsets.map { ComboBoxItem<String>(value: $0.name, child: Text($0.name, style: fluent.typography.body)) },
                    onChanged: { [weak self] v in
                        guard let self, let v, let i = SymbolData.subsets.firstIndex(where: { $0.name == v }) else { return }
                        self.setState { self.subset = i }
                    })),
            ]),
            SizedBox(width: nil, height: 10, child: nil),
            SizedBox(width: nil, height: 210, child: SingleChildScrollView(
                child: Column(crossAxisAlignment: .start, children: rows(SymbolData.characters(in: range), prefix: "sym-")))),
            SizedBox(width: nil, height: 10, child: nil),
            Text("Recently used", style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)),
            Row(children: recent.isEmpty ? [SizedBox(width: nil, height: 30, child: nil)]
                : recent.prefix(14).map { cell($0, "rec-" + String($0, radix: 16, uppercase: true)) }),
            SizedBox(width: nil, height: 10, child: nil),
            Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 90, height: nil, child: Text("Character code", style: fluent.typography.body)),
                SizedBox(width: 110, height: Chrome.fieldHeight, child: PKeyed("sym-code", FluentTextBox(
                    controller: _code, onSubmitted: { [weak self] _ in self?.insertSelected() }))),
            ]),
            SizedBox(width: nil, height: 8, child: nil),
            Text(status, style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)),
        ]
        return DialogShell(title: "Symbol", page: Column(crossAxisAlignment: .stretch, children: page),
                           okLabel: "Insert", cancelLabel: "Close", width: 560,
                           onOK: { [weak self] in self?.insertSelected() }, onCancel: _w.onClose)
    }
}
