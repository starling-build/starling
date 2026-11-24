// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-FM-1: the Format Cells dialog (⌘1 / Ctrl+1, the Home tab's Format button,
// the cell context menu). It starts from the active cell's format, and on OK
// hands back only what changed (CellFormatEdit), so the other cells of a
// selection keep their own fonts and fills. Tabs hold what the model keeps
// today; custom number codes (X-FM-2), border lines and colours (X-FM-3) and
// indent and orientation (X-FM-4) add to them in their own changes.

import Flutter
import FlutterSwiftBridge

final class FormatCellsDialog: StatefulWidget {
    let start: CellFormatEdit.Values
    let onApply: (CellFormatEdit) -> Void
    let onClose: () -> Void
    init(start: CellFormatEdit.Values, onApply: @escaping (CellFormatEdit) -> Void, onClose: @escaping () -> Void) {
        self.start = start; self.onApply = onApply; self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { FormatCellsDialogState() }

    static let numberFormats: [(String, String)] = [
        ("General", "General"), ("Number", "0.00"), ("Currency", "$#,##0.00"),
        ("Percentage", "0.00%"), ("Scientific", "0.00E+00"), ("Text", "@"),
    ]
    static let swatches: [(String, UInt32)] = [
        ("Black", 0x000000), ("White", 0xFFFFFF), ("Dark Gray", 0x595959), ("Light Gray", 0xD9D9D9),
        ("Dark Red", 0xC00000), ("Red", 0xFF0000), ("Orange", 0xFFC000), ("Yellow", 0xFFFF00),
        ("Light Green", 0x92D050), ("Green", 0x00B050), ("Light Blue", 0x00B0F0), ("Blue", 0x0070C0),
        ("Dark Blue", 0x002060), ("Purple", 0x7030A0),
    ]
}

final class FormatCellsDialogState: State<StatefulWidget> {
    private var _w: FormatCellsDialog { widget as! FormatCellsDialog }
    /// The values the dialog shows; `_w.start` is what they are compared with on OK.
    private(set) var values: CellFormatEdit.Values!
    private let _fontName = TextEditingController()
    private let _fontSize = TextEditingController()

    override func initState() {
        super.initState()
        values = _w.start
        _fontName.text = values.fontName ?? ""
        _fontSize.text = values.fontSize.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? ""
    }

    override func dispose() {
        _fontName.dispose(); _fontSize.dispose()
        super.dispose()
    }

    private func _set(_ change: (inout CellFormatEdit.Values) -> Void) { setState { change(&values) } }

    private func _ok() {
        _w.onApply(CellFormatEdit.between(_w.start, values))
        _w.onClose()
    }

    override func build(_ context: BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        return DialogShell(
            title: "Format Cells",
            tabs: [
                DialogTab(title: "Number", page: _numberPage(fluent)),
                DialogTab(title: "Alignment", page: _alignmentPage(fluent)),
                DialogTab(title: "Font", page: _fontPage(fluent)),
                DialogTab(title: "Border", page: _borderPage(fluent)),
                DialogTab(title: "Fill", page: _fillPage(fluent)),
            ],
            width: 480, onOK: { [weak self] in self?._ok() }, onCancel: { [weak self] in self?._w.onClose() })
    }

    // MARK: pages

    private func _column(_ rows: [Widget]) -> Widget {
        Padding(padding: EdgeInsets(all: 8), child: Column(crossAxisAlignment: .start, children: rows))
    }

    private func _choice(_ id: String, _ label: String, selected: Bool, _ action: @escaping () -> Void) -> Widget {
        SizedBox(key: ValueKey(id), width: nil, height: 28, child: FlatButton(
            child: Padding(padding: EdgeInsets(left: 8, top: 0, right: 8, bottom: 0), child: Text(label)),
            checked: selected, width: nil, height: 28, alignLeft: true, action: action))
    }

    private func _check(_ id: String, _ label: String, _ on: Bool, _ set: @escaping (inout CellFormatEdit.Values, Bool) -> Void) -> Widget {
        Checkbox(key: ValueKey(id), checked: on, onChanged: { [weak self] v in self?._set { set(&$0, v ?? false) } }, content: Text(label))
    }

    private func _numberPage(_ fluent: FluentThemeData) -> Widget {
        let code = values.numberFormat
        let sample = NumberFormat.format(1234.5678, code).text
        let named = FormatCellsDialog.numberFormats.first { $0.1 == code }?.0
        return _column([
            Text("Category", style: fluent.typography.bodyStrong),
            Column(crossAxisAlignment: .stretch, children: FormatCellsDialog.numberFormats.map { name, c in
                _choice("fc-num-\(name)", name, selected: code == c) { [weak self] in self?._set { $0.numberFormat = c } }
            }),
            // (A code the file holds that is not in the list stays: it is named here, and kept unless another is picked.)
            Text(named == nil ? "Custom: \(code)" : "Format code: \(code)", style: fluent.typography.caption),
            Text("Sample: \(sample)", style: fluent.typography.caption),
        ])
    }

    private func _alignmentPage(_ fluent: FluentThemeData) -> Widget {
        let h: [(String, CellStyle.HAlign)] = [("General", .general), ("Left", .left), ("Center", .center), ("Right", .right)]
        let v: [(String, CellStyle.VAlign)] = [("Top", .top), ("Middle", .center), ("Bottom", .bottom)]
        return _column([
            Text("Horizontal", style: fluent.typography.bodyStrong),
            Row(children: h.map { n, a in _choice("fc-h-\(n)", n, selected: values.hAlign == a) { [weak self] in self?._set { $0.hAlign = a } } }),
            Text("Vertical", style: fluent.typography.bodyStrong),
            Row(children: v.map { n, a in _choice("fc-v-\(n)", n, selected: values.vAlign == a) { [weak self] in self?._set { $0.vAlign = a } } }),
            _check("fc-wrap", "Wrap text", values.wrap) { $0.wrap = $1 },
        ])
    }

    private func _fontPage(_ fluent: FluentThemeData) -> Widget {
        _column([
            Row(children: [
                SizedBox(width: 60, child: Text("Font")),
                SizedBox(key: ValueKey("fc-font-name"), width: 200, height: 30, child: FluentTextBox(controller: _fontName, onChanged: { [weak self] t in
                    self?._set { $0.fontName = t.isEmpty ? nil : t }
                })),
            ]),
            Row(children: [
                SizedBox(width: 60, child: Text("Size")),
                SizedBox(key: ValueKey("fc-font-size"), width: 80, height: 30, child: FluentTextBox(controller: _fontSize, onChanged: { [weak self] t in
                    // (Text that is not a size leaves the size as it was.)
                    if let z = Double(t), z > 0, z < 410 { self?._set { $0.fontSize = z } } else if t.isEmpty { self?._set { $0.fontSize = nil } }
                })),
            ]),
            Row(children: [
                _check("fc-bold", "Bold", values.bold) { $0.bold = $1 },
                _check("fc-italic", "Italic", values.italic) { $0.italic = $1 },
                _check("fc-underline", "Underline", values.underline) { $0.underline = $1 },
                _check("fc-strike", "Strikethrough", values.strike) { $0.strike = $1 },
            ]),
            Text("Text colour", style: fluent.typography.bodyStrong),
            _swatches("fc-color", values.color, noneLabel: "Automatic") { [weak self] c in self?._set { $0.color = c } },
        ])
    }

    private func _borderPage(_ fluent: FluentThemeData) -> Widget {
        _column([
            Text("Draw a line on", style: fluent.typography.bodyStrong),
            _check("fc-border-top", "Top", values.top) { $0.top = $1 },
            _check("fc-border-left", "Left", values.left) { $0.left = $1 },
            _check("fc-border-bottom", "Bottom", values.bottom) { $0.bottom = $1 },
            _check("fc-border-right", "Right", values.right) { $0.right = $1 },
            Row(children: [
                _choice("fc-border-all", "All sides", selected: false) { [weak self] in self?._set { $0.top = true; $0.left = true; $0.bottom = true; $0.right = true } },
                _choice("fc-border-none", "None", selected: false) { [weak self] in self?._set { $0.top = false; $0.left = false; $0.bottom = false; $0.right = false } },
            ]),
        ])
    }

    private func _fillPage(_ fluent: FluentThemeData) -> Widget {
        _column([
            Text("Background colour", style: fluent.typography.bodyStrong),
            _swatches("fc-fill", values.fill, noneLabel: "No fill") { [weak self] c in self?._set { $0.fill = c } },
        ])
    }

    private func _swatches(_ id: String, _ current: UInt32?, noneLabel: String, _ pick: @escaping (UInt32?) -> Void) -> Widget {
        Column(crossAxisAlignment: .start, children: [
            _choice("\(id)-none", noneLabel, selected: current == nil) { pick(nil) },
            Wrap(spacing: 4, runSpacing: 4, children: FormatCellsDialog.swatches.map { name, rgb in
                SizedBox(key: ValueKey("\(id)-\(name)"), width: 28, height: 28, child: FlatButton(
                    child: DecoratedBox(decoration: BoxDecoration(color: Color(Int64(0xFF000000 | rgb))), child: SizedBox(width: 18, height: 18)),
                    tip: name, checked: current == rgb, action: { pick(rgb) }))
            }),
        ])
    }
}
