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
        ("Latin Extended-A", 0x100 ... 0x17F), ("Latin Extended-B", 0x180 ... 0x24F),
        ("IPA Extensions", 0x250 ... 0x2AF), ("Spacing Modifier Letters", 0x2B0 ... 0x2FF),
        ("Greek and Coptic", 0x370 ... 0x3FF), ("Cyrillic", 0x400 ... 0x4FF),
        ("Hebrew", 0x590 ... 0x5FF), ("Arabic", 0x600 ... 0x6FF),
        ("Latin Extended Additional", 0x1E00 ... 0x1EFF), ("General Punctuation", 0x2000 ... 0x206F),
        ("Superscripts and Subscripts", 0x2070 ... 0x209F), ("Currency Symbols", 0x20A0 ... 0x20CF),
        ("Letterlike Symbols", 0x2100 ... 0x214F), ("Number Forms", 0x2150 ... 0x218F),
        ("Arrows", 0x2190 ... 0x21FF), ("Mathematical Operators", 0x2200 ... 0x22FF),
        ("Miscellaneous Technical", 0x2300 ... 0x23FF), ("Enclosed Alphanumerics", 0x2460 ... 0x24FF),
        ("Box Drawing", 0x2500 ... 0x257F), ("Block Elements", 0x2580 ... 0x259F),
        ("Geometric Shapes", 0x25A0 ... 0x25FF), ("Miscellaneous Symbols", 0x2600 ... 0x26FF),
        ("Dingbats", 0x2700 ... 0x27BF), ("Alphabetic Presentation Forms", 0xFB00 ... 0xFB4F),
    ]

    /// The subset `v` is in, if any.
    static func subset(containing v: UInt32) -> Int? {
        subsets.firstIndex { $0.range.contains(v) }
    }

    /// Word's Special Characters tab, in Word's order, with Word for Windows' shortcut keys.
    static let specials: [(name: String, code: UInt32, shortcut: String)] = [
        ("Em Dash", 0x2014, "Alt+Ctrl+Num -"), ("En Dash", 0x2013, "Ctrl+Num -"),
        ("Nonbreaking Hyphen", 0x2011, "Ctrl+Shift+_"), ("Optional Hyphen", 0x00AD, "Ctrl+-"),
        ("Em Space", 0x2003, ""), ("En Space", 0x2002, ""), ("1/4 Em Space", 0x2005, ""),
        ("Nonbreaking Space", 0x00A0, "Ctrl+Shift+Space"),
        ("Copyright", 0x00A9, "Alt+Ctrl+C"), ("Registered", 0x00AE, "Alt+Ctrl+R"), ("Trademark", 0x2122, "Alt+Ctrl+T"),
        ("Section", 0x00A7, ""), ("Paragraph", 0x00B6, ""), ("Ellipsis", 0x2026, "Alt+Ctrl+."),
        ("Single Opening Quote", 0x2018, "Ctrl+`,`"), ("Single Closing Quote", 0x2019, "Ctrl+','"),
        ("Double Opening Quote", 0x201C, "Ctrl+`,\""), ("Double Closing Quote", 0x201D, "Ctrl+',\""),
        ("No-Width Optional Break", 0x200C, ""), ("No-Width Non Break", 0x200D, ""),
    ]

    /// What Word's Insert > Symbol gallery holds before anything has been used.
    static let galleryDefaults: [UInt32] = [0x20AC, 0xA3, 0xA5, 0xA9, 0xAE, 0x2122, 0xB1, 0x2260, 0x2264, 0x2265,
                                            0xF7, 0xD7, 0x221E, 0xB5, 0x3B1, 0x3B2, 0x3C0, 0x3A9, 0x2211, 0x263A]

    /// The gallery: the most recently used first, filled up to 20 from Word's defaults.
    static func gallery(_ recent: [UInt32]) -> [UInt32] {
        Array((recent + galleryDefaults.filter { !recent.contains($0) }).prefix(20))
    }

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
    /// With `decimal` (Word's "from: ASCII (decimal)") the code is a decimal number instead.
    static func parseCode(_ text: String, decimal: Bool = false) -> UInt32? {
        var t = text.trimmingWhitespace().lowercased()
        if !decimal { for p in ["u+", "0x", "x"] where t.hasPrefix(p) { t = String(t.dropFirst(p.count)); break } }
        guard !t.isEmpty, t.count <= 7, let v = UInt32(t, radix: decimal ? 10 : 16), let u = Unicode.Scalar(v) else { return nil }
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
    /// 0 Symbols, 1 Special Characters (Word's two tabs).
    private(set) var tab = 0
    private(set) var subset = 1
    private(set) var fontIndex = 0
    private(set) var selected: UInt32? = nil
    /// The row picked on Special Characters.
    private(set) var special = 0
    /// Word's "from:": the code box in ASCII (decimal) rather than Unicode (hex).
    private(set) var decimal = false
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

    func setTab(_ t: Int) { setState { tab = t; status = "" } }

    private func _codeText(_ v: UInt32) -> String { decimal ? String(v) : String(v, radix: 16, uppercase: true) }

    /// Pick `v`; like Word, the Subset box follows to the block the character is in.
    func choose(_ v: UInt32) {
        setState {
            selected = v
            if let k = SymbolData.subset(containing: v) { subset = k }
            _code.text = _codeText(v)
            status = SymbolData.code(v) + "  " + SymbolData.name(v)
        }
    }

    /// Switch the code box between hex and decimal, keeping the character.
    func setDecimal(_ on: Bool) {
        let v = SymbolData.parseCode(_code.text, decimal: decimal) ?? selected
        setState {
            decimal = on
            _code.text = v.map(_codeText) ?? ""
        }
    }

    func chooseSpecial(_ i: Int) {
        setState { special = i; status = SymbolData.code(SymbolData.specials[i].code) + "  " + SymbolData.specials[i].name }
    }

    func insertSelected() {
        if tab == 1 {
            // Special characters go in the current font, as Word's.
            let sp = SymbolData.specials[special]
            guard let u = Unicode.Scalar(sp.code) else { return }
            _w.hooks.insert(String(Character(u)), nil)
            setState { status = "Inserted " + sp.name }
            return
        }
        // A code typed by hand wins over the last click.
        if let v = SymbolData.parseCode(_code.text, decimal: decimal) { selected = v }
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
        let body = fluent.typography.body
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        func cell(_ v: UInt32, _ key: String) -> Widget {
            let on = selected == v
            return PKeyed(key, SizedBox(width: 30, height: 30, child: Button(
                onPressed: { [weak self] in self?.choose(v) },
                child: Text(String(Character(Unicode.Scalar(v) ?? " ")),
                            style: body?.copyWith(fontWeight: on ? .bold : nil, fontFamily: face)))))
        }
        func rows(_ list: [UInt32], prefix: String) -> [Widget] {
            stride(from: 0, to: list.count, by: 14).map { i in
                Row(children: list[i ..< min(i + 14, list.count)].map { cell($0, prefix + String($0, radix: 16, uppercase: true)) })
            }
        }
        let range = SymbolData.subsets[subset].range
        let symbols: [Widget] = [
            Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 44, height: nil, child: Text("Font", style: body)),
                SizedBox(width: 190, height: nil, child: ComboBox<String>(
                    value: h.fonts[fontIndex],
                    items: h.fonts.map { ComboBoxItem<String>(value: $0, child: Text($0, style: body)) },
                    onChanged: { [weak self] v in
                        guard let self, let v, let i = h.fonts.firstIndex(of: v) else { return }
                        self.setState { self.fontIndex = i }
                    })),
                SizedBox(width: 16, height: nil, child: nil),
                SizedBox(width: 56, height: nil, child: Text("Subset", style: body)),
                Expanded(child: PKeyed("sym-subset", ComboBox<String>(
                    value: SymbolData.subsets[subset].name,
                    items: SymbolData.subsets.map { ComboBoxItem<String>(value: $0.name, child: Text($0.name, style: body)) },
                    onChanged: { [weak self] v in
                        guard let self, let v, let i = SymbolData.subsets.firstIndex(where: { $0.name == v }) else { return }
                        self.setState { self.subset = i }
                    }))),
            ]),
            SizedBox(width: nil, height: 10, child: nil),
            SizedBox(width: nil, height: 210, child: SingleChildScrollView(
                child: Column(crossAxisAlignment: .start, children: rows(SymbolData.characters(in: range), prefix: "sym-")))),
            SizedBox(width: nil, height: 10, child: nil),
            Text("Recently used symbols", style: caption),
            Row(children: recent.isEmpty ? [SizedBox(width: nil, height: 30, child: nil)]
                : recent.prefix(14).map { cell($0, "rec-" + String($0, radix: 16, uppercase: true)) }),
            SizedBox(width: nil, height: 10, child: nil),
            Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 100, height: nil, child: Text("Character code", style: body)),
                SizedBox(width: 110, height: Chrome.fieldHeight, child: PKeyed("sym-code", FluentTextBox(
                    controller: _code, onSubmitted: { [weak self] _ in self?.insertSelected() }))),
                SizedBox(width: 20, height: nil, child: nil),
                SizedBox(width: 45, height: nil, child: Text("from", style: body)),
                SizedBox(width: 160, height: nil, child: PKeyed("sym-from", ComboBox<Bool>(
                    value: decimal,
                    items: [ComboBoxItem<Bool>(value: false, child: Text("Unicode (hex)", style: body)),
                            ComboBoxItem<Bool>(value: true, child: Text("ASCII (decimal)", style: body))],
                    onChanged: { [weak self] v in if let v { self?.setDecimal(v) } }))),
            ]),
        ]
        // Special Characters: Word's list of name and shortcut key; click one, then Insert.
        let specials: [Widget] = [
            Row(children: [
                SizedBox(width: 40, height: nil, child: nil),
                Expanded(child: Text("Character", style: caption)),
                SizedBox(width: 170, height: nil, child: Text("Shortcut key", style: caption)),
            ]),
            SizedBox(width: nil, height: 4, child: nil),
            Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: .stretch, children:
                SymbolData.specials.enumerated().map { i, sp in
                    let on = special == i
                    let pick: () -> Void = { [weak self] in self?.chooseSpecial(i) }
                    return PKeyed("spc-\(i)", KeyboardRow(label: sp.name, activate: pick, child: GestureDetector(onTap: pick, behavior: .opaque, child: ColoredBox(
                        color: on ? fluent.resources.subtleFillColorSecondary : Color(0x00000000),
                        child: Padding(padding: EdgeInsets(left: 6, top: 3, right: 6, bottom: 3), child: Row(children: [
                            SizedBox(width: 34, height: nil, child: Text(String(Character(Unicode.Scalar(sp.code) ?? " ")), style: body)),
                            Expanded(child: Text(sp.name, style: on ? fluent.typography.bodyStrong : body)),
                            SizedBox(width: 170, height: nil, child: Text(sp.shortcut, style: body)),
                        ]))))))
                }))),
        ]
        // Word keeps the dialog one size on both tabs: Special Characters sits over a hidden
        // Symbols page, which sets the height.
        let symbolsPage = Column(crossAxisAlignment: .stretch, children: symbols)
        let content: Widget = tab == 0 ? symbolsPage : Stack(children: [
            IgnorePointer(child: ExcludeSemantics(child: Opacity(opacity: 0, child: symbolsPage))),
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: Column(crossAxisAlignment: .stretch, children: specials)),
        ])
        func tabButton(_ key: String, _ name: String, _ t: Int) -> Widget {
            PKeyed(key, Chrome.textToggle(name, tab == t, fluent) { [weak self] in self?.setTab(t) })
        }
        let page: [Widget] = [
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 12), child: Row(children: [
                tabButton("sym-tab-symbols", "Symbols", 0), tabButton("sym-tab-special", "Special Characters", 1),
            ])),
            content,
            SizedBox(width: nil, height: 8, child: nil),
            Text(status.isEmpty ? " " : status, style: caption),  // a blank line held, so the dialog does not move
        ]
        return DialogShell(title: "Symbol", page: Column(crossAxisAlignment: .stretch, children: page),
                           okLabel: "Insert", cancelLabel: "Close", width: 560,
                           onOK: { [weak self] in self?.insertSelected() }, onCancel: _w.onClose)
    }
}
