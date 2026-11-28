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
    /// The tab to open on (3 is Border).
    var startTab = 0
    init(start: CellFormatEdit.Values, onApply: @escaping (CellFormatEdit) -> Void, onClose: @escaping () -> Void) {
        self.start = start; self.onApply = onApply; self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { FormatCellsDialogState() }

    static let numberFormats: [(String, String)] = [
        ("General", "General"), ("Number", "0.00"), ("Currency", "$#,##0.00"),
        ("Percentage", "0.00%"), ("Scientific", "0.00E+00"), ("Text", "@"),
        ("Thousands", "#,##0"), ("Negative red", "#,##0.00;[Red]-#,##0.00"), ("Fraction", "# ?/?"),
        ("Date", "yyyy-mm-dd"), ("Time", "h:mm:ss"), ("Date and time", "yyyy-mm-dd h:mm"), ("Elapsed", "[h]:mm:ss"),
    ]
    /// The line styles a side can take (the names the file format uses).
    static let lineKinds: [(String, String)] = [
        ("Thin", "thin"), ("Medium", "medium"), ("Thick", "thick"), ("Double", "double"),
        ("Dashed", "dashed"), ("Dotted", "dotted"), ("Hair", "hair"),
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
    private let _code = TextEditingController()
    /// Why the typed code cannot be kept (nil when it can); OK waits until it can.
    private(set) var codeProblem: String?

    override func initState() {
        super.initState()
        values = _w.start
        _code.text = values.numberFormat
        _fontName.text = values.fontName ?? ""
        _fontSize.text = values.fontSize.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? ""
    }

    override func dispose() {
        _fontName.dispose(); _fontSize.dispose(); _code.dispose()
        super.dispose()
    }

    private func _set(_ change: (inout CellFormatEdit.Values) -> Void) { setState { change(&values) } }

    private func _ok() {
        if codeProblem != nil { return }
        _w.onApply(CellFormatEdit.between(_w.start, values))
        _w.onClose()
    }

    override func build(_ context: BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let shell = DialogShell(
            title: "Format Cells",
            tabs: [
                DialogTab(title: "Number", page: _numberPage(fluent)),
                DialogTab(title: "Alignment", page: _alignmentPage(fluent)),
                DialogTab(title: "Font", page: _fontPage(fluent)),
                DialogTab(title: "Border", page: _borderPage(fluent)),
                DialogTab(title: "Fill", page: _fillPage(fluent)),
                DialogTab(title: "Protection", page: _protectionPage(fluent)),
            ],
            width: 480, onOK: { [weak self] in self?._ok() }, onCancel: { [weak self] in self?._w.onClose() })
        shell.startTab = _w.startTab
        return shell
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

    /// A check box in a row of them: each gets its own column, so a label never runs into the next box.
    private func _rowCheck(_ id: String, _ label: String, _ on: Bool, _ set: @escaping (inout CellFormatEdit.Values, Bool) -> Void) -> Widget {
        SizedBox(width: 130, child: _check(id, label, on, set))
    }

    /// Picking a ready-made format also fills the code box, so it can be edited from there.
    private func _pickFormat(_ c: String) {
        _code.text = c
        setState { codeProblem = nil; values.numberFormat = c }
    }

    private func _typeCode(_ t: String) {
        setState {
            codeProblem = NumberFormat.problem(t)
            if codeProblem == nil { values.numberFormat = t }
        }
    }

    private func _numberPage(_ fluent: FluentThemeData) -> Widget {
        let code = values.numberFormat
        func sample(_ v: CellValue) -> String { NumberFormat.display(v, code).text }
        let named = FormatCellsDialog.numberFormats.first { $0.1 == code }?.0
        return _column([
            Text("Category", style: fluent.typography.bodyStrong),
            Wrap(spacing: 4, runSpacing: 2, children: FormatCellsDialog.numberFormats.map { name, c in
                SizedBox(width: 140, child: _choice("fc-num-\(name)", name, selected: code == c) { [weak self] in self?._pickFormat(c) })
            }),
            Row(children: [
                SizedBox(width: 90, child: Text("Format code")),
                SizedBox(key: ValueKey("fc-num-code"), width: 300, height: Chrome.fieldHeight, child: FluentTextBox(controller: _code, onChanged: { [weak self] t in self?._typeCode(t) })),
            ]),
            Text(codeProblem ?? (named == nil ? "Custom format" : "Ready-made format: \(named!)"), style: fluent.typography.caption),
            Text("Positive: \(sample(.number(1234.5678)))    Negative: \(sample(.number(-1234.5678)))", style: fluent.typography.caption),
            Text("Zero: \(sample(.number(0)))    Text: \(sample(.text("abc")))", style: fluent.typography.caption),
        ])
    }

    /// Indent steps: more or fewer; text that is not yet aligned to a side moves to the left, as Excel does.
    private func _indent(_ by: Int) {
        _set {
            $0.indent = max(0, min(15, $0.indent + by))
            if $0.indent > 0, $0.hAlign == .general || $0.hAlign == .center { $0.hAlign = .left }
        }
    }

    private func _alignmentPage(_ fluent: FluentThemeData) -> Widget {
        let h: [(String, CellStyle.HAlign)] = [("General", .general), ("Left", .left), ("Center", .center), ("Right", .right)]
        let v: [(String, CellStyle.VAlign)] = [("Top", .top), ("Middle", .center), ("Bottom", .bottom)]
        // Rotation: the quarter turns the sheet draws; any other angle in the file is kept until one of these is picked.
        let r: [(String, Int)] = [("Horizontal", 0), ("Up", 90), ("Down", 180)]
        let turned = r.contains { $0.1 == values.rotation }
        let degrees = values.rotation > 90 ? values.rotation - 90 : values.rotation
        let note = (values.rotation == 255 ? "Stacked text" : "Text turned \(degrees) degrees") + " in the file; kept unless you pick one above."
        return _column([
            Text("Horizontal", style: fluent.typography.bodyStrong),
            Row(children: h.map { n, a in
                _choice("fc-h-\(n)", n, selected: values.hAlign == a && !values.justify) { [weak self] in self?._set { $0.hAlign = a; $0.justify = false } }
            } + [
                _choice("fc-h-Justify", "Justify", selected: values.justify) { [weak self] in self?._set { $0.hAlign = .left; $0.justify = true; $0.wrap = true } },
            ]),
            Row(children: [
                SizedBox(width: 60, child: Text("Indent")),
                SizedBox(key: ValueKey("fc-indent-less"), width: nil, height: 28, child: FlatButton(child: Text("−"), checked: false, width: 32, height: 28, action: { [weak self] in self?._indent(-1) })),
                SizedBox(width: 40, child: Center(child: Text("\(values.indent)"))),
                SizedBox(key: ValueKey("fc-indent-more"), width: nil, height: 28, child: FlatButton(child: Text("+"), checked: false, width: 32, height: 28, action: { [weak self] in self?._indent(1) })),
            ]),
            Text("Vertical", style: fluent.typography.bodyStrong),
            Row(children: v.map { n, a in _choice("fc-v-\(n)", n, selected: values.vAlign == a) { [weak self] in self?._set { $0.vAlign = a } } }),
            Text("Text direction", style: fluent.typography.bodyStrong),
            Row(children: r.map { n, d in _choice("fc-rot-\(n)", n, selected: values.rotation == d) { [weak self] in self?._set { $0.rotation = d } } }),
            turned ? SizedBox(width: 1, height: 1) : Text(note, style: fluent.typography.caption),
            _check("fc-wrap", "Wrap text", values.wrap) { $0.wrap = $1 },
            _check("fc-shrink", "Shrink to fit", values.shrink) { $0.shrink = $1 },
        ])
    }

    private func _fontPage(_ fluent: FluentThemeData) -> Widget {
        _column([
            Row(children: [
                SizedBox(width: 60, child: Text("Font")),
                SizedBox(key: ValueKey("fc-font-name"), width: 200, height: Chrome.fieldHeight, child: FluentTextBox(controller: _fontName, onChanged: { [weak self] t in
                    self?._set { $0.fontName = t.isEmpty ? nil : t }
                })),
            ]),
            Row(children: [
                SizedBox(width: 60, child: Text("Size")),
                SizedBox(key: ValueKey("fc-font-size"), width: 80, height: Chrome.fieldHeight, child: FluentTextBox(controller: _fontSize, onChanged: { [weak self] t in
                    // (Text that is not a size leaves the size as it was.)
                    if let z = Double(t), z > 0, z < 410 { self?._set { $0.fontSize = z } } else if t.isEmpty { self?._set { $0.fontSize = nil } }
                })),
            ]),
            Row(children: [
                _rowCheck("fc-bold", "Bold", values.bold) { $0.bold = $1 },
                _rowCheck("fc-italic", "Italic", values.italic) { $0.italic = $1 },
                _rowCheck("fc-underline", "Underline", values.underline) { $0.underline = $1 },
            ]),
            Row(children: [
                // Excel's Effects: Strikethrough, Superscript, Subscript. The two scripts are exclusive,
                // so ticking one clears the other.
                _rowCheck("fc-strike", "Strikethrough", values.strike) { $0.strike = $1 },
                _rowCheck("fc-superscript", "Superscript", values.script == 1) { $0.script = $1 ? 1 : 0 },
                _rowCheck("fc-subscript", "Subscript", values.script == -1) { $0.script = $1 ? -1 : 0 },
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
            Text("Line style", style: fluent.typography.bodyStrong),
            Wrap(spacing: 4, runSpacing: 4, children: FormatCellsDialog.lineKinds.map { name, kind in
                SizedBox(width: 90, height: 28, child: _choice("fc-line-\(name)", name, selected: values.lineKind == kind) { [weak self] in
                    self?._set { $0.lineKind = kind }
                })
            }),
            Text("Line colour", style: fluent.typography.bodyStrong),
            _swatches("fc-line-color", values.lineColor, noneLabel: "Automatic") { [weak self] c in self?._set { $0.lineColor = c } },
        ])
    }

    private func _protectionPage(_ fluent: FluentThemeData) -> Widget {
        _column([
            _check("fc-locked", "Locked", values.locked) { $0.locked = $1 },
            _check("fc-hidden", "Hidden (hide the formula)", values.formulaHidden) { $0.formulaHidden = $1 },
            Text("Locking has no effect until the sheet is protected (Review > Protect Sheet).", style: fluent.typography.caption),
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
