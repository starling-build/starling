// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-LI-1: "Define New Multilevel List". Pick a level (1 to 9), then set its number style,
// the text around the numbers (`%1`..`%9` stand for the numbers of levels 1 to 9), where its
// numbering starts, and its two indents (the number's position and the text's). A preview
// shows levels 1 to 3 nested. OK applies all nine levels to the caret's list as one
// undoable step (`setMultilevelFormat`). Per level also: what follows the number (tab, space,
// nothing), the paragraph style the level is linked to, and Legal style numbering (every number
// in the label in digits). With `listStyleName` set it is "Define New List Style": a Name field,
// and OK names a new list style instead of changing the text.

import Flutter
import FlutterSwiftBridge
import OfficeText

private final class MLKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}

final class MultilevelListDialog: StatefulWidget {
    let initial: [ListLevelFormat]
    let startLevel: Int
    let onOK: ([ListLevelFormat]) -> Void
    let onCancel: () -> Void
    /// Styles a level can link to, as (the id a level stores, the name shown).
    let linkable: [(id: String, name: String)]
    /// Non-nil: Define New List Style, starting with this name.
    let listStyleName: String?
    let onOKNamed: (([ListLevelFormat], String) -> Void)?
    init(initial: [ListLevelFormat], startLevel: Int = 0, linkable: [(id: String, name: String)] = [],
         listStyleName: String? = nil, onOKNamed: (([ListLevelFormat], String) -> Void)? = nil,
         onOK: @escaping ([ListLevelFormat]) -> Void = { _ in }, onCancel: @escaping () -> Void) {
        self.initial = initial; self.startLevel = startLevel; self.onOK = onOK; self.onCancel = onCancel
        self.linkable = linkable; self.listStyleName = listStyleName; self.onOKNamed = onOKNamed
        super.init()
    }
    override func createState() -> State<StatefulWidget> { MultilevelListDialogState() }
}

final class MultilevelListDialogState: State<StatefulWidget> {
    private var _w: MultilevelListDialog { widget as! MultilevelListDialog }
    private(set) var levels: [ListLevelFormat] = []
    private(set) var level = 0
    /// Fields holding something that is not a valid value, as "level|field".
    private var _bad = Set<String>()
    private let _text = TextEditingController()
    private let _start = TextEditingController()
    private let _aligned = TextEditingController()
    private let _indent = TextEditingController()
    private let _name = TextEditingController()

    static let follows: [(id: String, title: String)] = [("tab", "Tab character"), ("space", "Space"), ("nothing", "Nothing")]
    static let noStyle = "(no style)"

    static let styles: [(id: String, title: String, format: ListNumberFormat)] = [
        ("decimal", "1, 2, 3", .decimal), ("lower-letter", "a, b, c", .lowerLetter),
        ("upper-letter", "A, B, C", .upperLetter), ("lower-roman", "i, ii, iii", .lowerRoman),
        ("upper-roman", "I, II, III", .upperRoman), ("bullet", "Bullet", .bullet),
    ]

    override func initState() {
        super.initState()
        levels = Array(_w.initial.prefix(9))
        while levels.count < 9 { levels.append(.plain(levels.count)) }
        level = max(0, min(8, _w.startLevel))
        _name.text = _w.listStyleName ?? ""
        _load()
    }

    private static func pt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }

    /// Fill the fields from the chosen level.
    private func _load() {
        let f = levels[level]
        _text.text = f.text
        _start.text = String(f.start ?? 1)
        let left = f.indentLeft ?? Double(36 * (level + 1)), hang = f.hanging ?? 18
        _aligned.text = Self.pt(left - hang)
        _indent.text = Self.pt(left)
    }

    /// Read the fields back into the chosen level.
    private func _store() {
        var f = levels[level]
        let key = "\(level)|"
        _bad = _bad.filter { !$0.hasPrefix(key) }
        if _text.text.isEmpty { _bad.insert(key + "text") } else { f.text = _text.text }
        if f.format != .bullet {
            if let n = Int(_start.text.trimmingWhitespace()), n >= 0, n <= 32767 { f.start = n == 1 ? nil : n } else { _bad.insert(key + "start") }
        }
        let a = Double(_aligned.text.trimmingWhitespace()), t = Double(_indent.text.trimmingWhitespace())
        if let a, let t, a >= 0, t >= 0, a <= 1584, t <= 1584 {
            f.indentLeft = t
            f.hanging = t - a
        } else { _bad.insert(key + "indent") }
        levels[level] = f
    }

    private func _pick(_ l: Int) { setState { level = l; _load() } }

    private func _setStyle(_ format: ListNumberFormat) {
        setState {
            var f = levels[level]
            let wasBullet = f.format == .bullet
            f.format = format
            f.rawFormat = nil
            if format == .bullet {
                f.text = ListLevelFormat.defaultBullet(level)
                f.start = nil
            } else if wasBullet {
                f.text = "%\(level + 1)."
            }
            levels[level] = f
            _load()
            _store()
        }
    }

    /// Follow number with: "tab" (Word's default, stored as none), "space" or "nothing".
    func setFollow(_ id: String) { setState { levels[level].suffix = id == "tab" ? nil : id } }
    /// Link level to style: the id to store, nil for none.
    func setLink(_ id: String?) { setState { levels[level].styleLink = id } }
    func setLegal(_ on: Bool) { setState { levels[level].legal = on ? true : nil } }
    func setName(_ name: String) { setState { _name.text = name } }

    /// The nine levels, or nil while a field holds something invalid (or the name is empty).
    var result: [ListLevelFormat]? {
        guard _bad.isEmpty else { return nil }
        if _w.listStyleName != nil, _name.text.trimmingWhitespace().isEmpty { return nil }
        return levels
    }

    private func _ok() {
        guard let r = result else { return }
        if _w.listStyleName != nil { _w.onOKNamed?(r, _name.text.trimmingWhitespace()) } else { _w.onOK(r) }
    }

    /// The label level `l` shows for its first item under the first items above it.
    func label(_ l: Int) -> String {
        let f = levels[l]
        if f.format == .bullet { return f.text }
        var out = ""
        var chars = f.text.makeIterator()
        while let ch = chars.next() {
            if ch == "%", let d = chars.next(), let k = Int(String(d)), k >= 1, k <= 9 {
                let src = levels[k - 1], n = max(1, src.start ?? 1)
                out += src.format == .bullet ? "" : f.legal == true ? String(n) : src.number(n)
            } else { out.append(ch) }
        }
        return out
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func row(_ label: String, _ items: [Widget]) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children:
                [SizedBox(width: 130, height: nil, child: Text(label))] + items))
        }
        func field(_ id: String, _ c: TextEditingController, width: Double = 90) -> Widget {
            SizedBox(width: width, height: Chrome.fieldHeight, child: MLKeyed(id, FluentTextBox(
                controller: c, onChanged: { [weak self] _ in self?.setState { self?._store() } },
                onSubmitted: { [weak self] _ in self?._ok() })))
        }
        let f = levels[level]
        var rows: [Widget] = []
        if _w.listStyleName != nil { rows.append(row("Name", [field("ml-name", _name, width: 220)])) }
        rows.append(row("Level to modify", (0 ..< 9).map { l in
            MLKeyed("ml-level-\(l + 1)", Chrome.textToggle("\(l + 1)", l == level, fluent) { [weak self] in self?._pick(l) })
        }))
        let styleButtons: [Widget] = Self.styles.map { s in
            MLKeyed("ml-style-\(s.id)", Chrome.textToggle(s.title, f.format == s.format && f.rawFormat == nil, fluent) { [weak self] in
                self?._setStyle(s.format)
            })
        }
        rows.append(row("Number style", [Column(crossAxisAlignment: .start, children: [
            Row(children: Array(styleButtons.prefix(3))), Row(children: Array(styleButtons.dropFirst(3))),
        ])]))
        rows.append(row(f.format == .bullet ? "Bullet" : "Number format", [field("ml-text", _text, width: 160)]))
        if f.format != .bullet { rows.append(row("Start at", [field("ml-start", _start)])) }
        rows.append(row("Aligned at (pt)", [field("ml-aligned", _aligned)]))
        rows.append(row("Text indent at (pt)", [field("ml-indent", _indent)]))
        rows.append(row("Follow number with", Self.follows.map { fo in
            MLKeyed("ml-follow-\(fo.id)", Chrome.textToggle(fo.title, (f.suffix ?? "tab") == fo.id, fluent) { [weak self] in self?.setFollow(fo.id) })
        }))
        let names = [Self.noStyle] + _w.linkable.map(\.name)
        let linked = f.styleLink.flatMap { id in _w.linkable.first { $0.id == id }?.name ?? id } ?? Self.noStyle
        rows.append(row("Link level to style", [SizedBox(width: 220, height: nil, child: MLKeyed("ml-link", ComboBox<String>(
            value: names.contains(linked) ? linked : Self.noStyle,
            items: names.map { ComboBoxItem<String>(value: $0, child: Text($0, style: fluent.typography.body)) },
            onChanged: { [weak self] v in
                guard let self, let v else { return }
                self.setLink(v == Self.noStyle ? nil : self._w.linkable.first { $0.name == v }?.id)
            })))]))
        rows.append(Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: MLKeyed("ml-legal", Checkbox(
            checked: f.legal == true, onChanged: { [weak self] c in self?.setLegal(c ?? false) },
            content: Text("Legal style numbering", style: fluent.typography.body)))))
        let preview = (0 ..< 3).map { l in
            String(repeating: "    ", count: l) + label(l) + " Level \(l + 1)"
        }
        rows.append(row("Preview", [MLKeyed("ml-preview", Column(crossAxisAlignment: .start, children: preview.map { Text($0) }))]))
        return DialogShell(title: _w.listStyleName != nil ? "Define New List Style" : "Define New Multilevel List",
                           page: Column(crossAxisAlignment: .start, children: rows),
                           okEnabled: result != nil, width: 520,
                           onOK: { [weak self] in self?._ok() },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
