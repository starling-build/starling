// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-LI-1: "Define New Multilevel List". Pick a level (1 to 9), then set its number style,
// the text around the numbers (`%1`..`%9` stand for the numbers of levels 1 to 9), where its
// numbering starts, and its two indents (the number's position and the text's). A preview
// shows levels 1 to 3 nested. OK applies all nine levels to the caret's list as one
// undoable step (`setMultilevelFormat`).

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
    init(initial: [ListLevelFormat], startLevel: Int = 0,
         onOK: @escaping ([ListLevelFormat]) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial; self.startLevel = startLevel; self.onOK = onOK; self.onCancel = onCancel
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

    /// The nine levels, or nil while a field holds something invalid.
    var result: [ListLevelFormat]? { _bad.isEmpty ? levels : nil }

    /// The label level `l` shows for its first item under the first items above it.
    func label(_ l: Int) -> String {
        let f = levels[l]
        if f.format == .bullet { return f.text }
        var out = ""
        var chars = f.text.makeIterator()
        while let ch = chars.next() {
            if ch == "%", let d = chars.next(), let k = Int(String(d)), k >= 1, k <= 9 {
                let src = levels[k - 1]
                out += src.format == .bullet ? "" : src.number(max(1, src.start ?? 1))
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
                onSubmitted: { [weak self] _ in if let r = self?.result { self?._w.onOK(r) } })))
        }
        let f = levels[level]
        var rows: [Widget] = []
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
        let preview = (0 ..< 3).map { l in
            String(repeating: "    ", count: l) + label(l) + " Level \(l + 1)"
        }
        rows.append(row("Preview", [MLKeyed("ml-preview", Column(crossAxisAlignment: .start, children: preview.map { Text($0) }))]))
        return DialogShell(title: "Define New Multilevel List",
                           page: Column(crossAxisAlignment: .start, children: rows),
                           okEnabled: result != nil, width: 520,
                           onOK: { [weak self] in if let r = self?.result { self?._w.onOK(r) } },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
