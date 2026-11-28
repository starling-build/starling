// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-PG-3: Design > Watermark > Custom Watermark, Design > Page Borders, and Layout > Line Numbers > Line Numbering
// Options. Each dialog only gathers the choice; the shell applies it as one undo step.

import Flutter
import FlutterSwiftBridge
import OfficeText

// MARK: Watermark

/// What the Printed Watermark dialog chose. A picture comes back as its path: the shell reads and measures it.
enum WatermarkChoice: Equatable {
    case none
    case text(WordWatermark.TextMark)
    case picture(path: String, scale: Double?, washout: Bool)
}

final class WatermarkDialog: StatefulWidget {
    let current: WordWatermark.TextMark?
    /// The host's file chooser, when it has one (nil: the path is typed).
    let pickPicture: ((@escaping (String?) -> Void) -> Void)?
    let onOK: (WatermarkChoice) -> Void
    let onCancel: () -> Void

    init(current: WordWatermark.TextMark?, pickPicture: ((@escaping (String?) -> Void) -> Void)?,
         onOK: @escaping (WatermarkChoice) -> Void, onCancel: @escaping () -> Void) {
        self.current = current; self.pickPicture = pickPicture; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { WatermarkDialogState() }
}

final class WatermarkDialogState: State<StatefulWidget> {
    enum Mode { case none, picture, text }
    private var _w: WatermarkDialog { widget as! WatermarkDialog }
    var mode = Mode.text
    var mark = WordWatermark.TextMark()
    let text = TextEditingController()
    let path = TextEditingController()
    var scale: Double? = nil
    var washout = true
    private var _colorOpen = false
    static let fonts = ["Calibri", "Calibri Light", "Arial", "Times New Roman", "Cambria", "Georgia", "Verdana"]
    static let sizes: [Double?] = [nil, 36, 40, 44, 48, 54, 60, 66, 72, 80, 90, 96, 105, 120, 144]
    static let scales: [Double?] = [nil, 0.5, 1, 1.5, 2, 5]

    override func initState() {
        super.initState()
        if let m = _w.current { mark = m }
        text.text = mark.text
    }

    func ok() { _w.onOK(choice()) }

    func choice() -> WatermarkChoice {
        switch mode {
        case .none: return .none
        case .picture: return path.text.isEmpty ? .none : .picture(path: path.text, scale: scale, washout: washout)
        case .text:
            var m = mark
            m.text = text.text
            return m.text.isEmpty ? .none : .text(m)
        }
    }


    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func toggle(_ key: String, _ label: String, _ on: Bool, _ f: @escaping () -> Void) -> Widget {
            PKeyed(key, Chrome.textToggle(label, on, fluent) { [weak self] in self?.setState { f() } })
        }
        func row(_ label: String, _ children: [Widget]) -> Widget {
            Row(crossAxisAlignment: .center, children: [SizedBox(width: 90, height: nil, child: Text(label, style: fluent.typography.body))] + children)
        }
        let on = fluent.typography.body
        var children: [Widget] = [
            Row(children: [toggle("wm-none", "No watermark", mode == .none) { self.mode = .none },
                           toggle("wm-picture", "Picture watermark", mode == .picture) { self.mode = .picture },
                           toggle("wm-text", "Text watermark", mode == .text) { self.mode = .text }]),
            Chrome.vgap(10),
        ]
        if mode == .picture {
            var pick: [Widget] = [Expanded(child: PKeyed("wm-path", SizedBox(width: nil, height: Chrome.fieldHeight, child: FluentTextBox(
                controller: path, onChanged: { [weak self] _ in self?.setState {} }))))]
            if let ask = _w.pickPicture {
                pick += [SizedBox(width: 8, height: nil), PKeyed("wm-select", Button(onPressed: { [weak self] in
                    ask { p in guard let self, let p else { return }; self.setState { self.path.text = p } }
                }, child: Text("Select Picture…")))]
            }
            children += [
                row("Picture:", pick), Chrome.vgap(8),
                row("Scale:", Self.scales.map { s in
                    toggle("wm-scale-\(s.map { String(Int($0 * 100)) } ?? "auto")", s.map { "\(Int($0 * 100))%" } ?? "Auto", scale == s) { self.scale = s }
                }), Chrome.vgap(8),
                PKeyed("wm-washout", Checkbox(checked: washout, onChanged: { [weak self] v in self?.setState { self?.washout = v ?? true } },
                                              content: Text("Washout", style: on))),
            ]
        } else if mode == .text {
            children += [
                row("Text:", [Expanded(child: PKeyed("wm-textbox", SizedBox(width: nil, height: Chrome.fieldHeight, child: FluentTextBox(
                    controller: text, onChanged: { [weak self] _ in self?.setState {} }))))]),
                Chrome.vgap(4),
                Wrap(spacing: 4, runSpacing: 4, children: WordWatermark.presets.map { p in
                    toggle("wm-preset-\(p)", p, text.text == p) { self.text.text = p } }),
                Chrome.vgap(8),
                row("Font:", [Wrap(spacing: 4, runSpacing: 4, children: Self.fonts.map { f in
                    toggle("wm-font-\(f)", f, mark.font == f) { self.mark.font = f } })]),
                Chrome.vgap(8),
                row("Size:", [Expanded(child: Wrap(spacing: 4, runSpacing: 4, children: Self.sizes.map { s in
                    toggle("wm-size-\(s.map { String(Int($0)) } ?? "auto")", s.map { String(Int($0)) } ?? "Auto", mark.size == s) { self.mark.size = s } }))]),
                Chrome.vgap(8),
                row("Color:", [PKeyed("wm-color", Chrome.textToggle(ColorMath.hex(mark.color), _colorOpen, fluent) { [weak self] in
                                   self?.setState { self?._colorOpen.toggle() } }),
                               Chrome.gap(6),
                               SizedBox(width: 18, height: 18, child: DecoratedBox(decoration: BoxDecoration(
                                   color: Color(Int64(0xFF000000) | Int64(mark.color)),
                                   border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1)))),
                               Chrome.gap(12),
                               PKeyed("wm-semi", Checkbox(checked: mark.semitransparent,
                                                          onChanged: { [weak self] v in self?.setState { self?.mark.semitransparent = v ?? true } },
                                                          content: Text("Semitransparent", style: on)))]),
            ]
            if _colorOpen {
                children.append(ColorPicker(onChoose: { [weak self] c in
                    self?.setState {
                        if let rgb = c.resolved(theme: ColorMath.officeTheme) { self?.mark.color = rgb }
                        self?._colorOpen = false
                    }
                }, onMore: {}))
            }
            children += [
                Chrome.vgap(8),
                row("Layout:", [toggle("wm-diagonal", "Diagonal", mark.diagonal) { self.mark.diagonal = true },
                                toggle("wm-horizontal", "Horizontal", !mark.diagonal) { self.mark.diagonal = false }]),
            ]
        }
        return DialogShell(title: "Printed Watermark", page: Column(crossAxisAlignment: .start, children: children), okEnabled: true, width: 560,
                           onOK: { [weak self] in self?.ok() },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}

// MARK: Page borders

final class PageBordersDialog: StatefulWidget {
    let initial: PageBorders?
    let onOK: (PageBorders?, RichDocumentController.PageBordersScope) -> Void
    let onCancel: () -> Void

    init(initial: PageBorders?, onOK: @escaping (PageBorders?, RichDocumentController.PageBordersScope) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { PageBordersDialogState() }
}

final class PageBordersDialogState: State<StatefulWidget> {
    enum Setting { case none, box, shadow }
    private var _w: PageBordersDialog { widget as! PageBordersDialog }
    var setting = Setting.none
    var b = PageBorders()
    var scope = RichDocumentController.PageBordersScope.wholeDocument
    private var _colorOpen = false
    static let styles: [(String, String)] = [("single", "Single"), ("double", "Double"), ("dotted", "Dotted"), ("dashed", "Dashed"),
                                             ("dotDash", "Dot dash"), ("triple", "Triple"), ("thickThinSmallGap", "Thick-thin"), ("thinThickSmallGap", "Thin-thick")]
    /// `w:sz` choices, eighths of a point (Word's ¼ pt … 6 pt).
    static let widths = [2, 4, 6, 8, 12, 18, 24, 36, 48]

    static func widthLabel(_ w: Int) -> String {
        switch w {
        case 2: return "¼ pt"
        case 4: return "½ pt"
        case 6: return "¾ pt"
        case 12: return "1½ pt"
        case 18: return "2¼ pt"
        case 36: return "4½ pt"
        default: return "\(w / 8) pt"
        }
    }

    override func initState() {
        super.initState()
        if let i = _w.initial, !i.sides.isEmpty {
            b = i
            setting = i.shadow ? .shadow : .box
            if i.display == "firstPage" { scope = .thisSectionFirstPage } else if i.display == "notFirstPage" { scope = .thisSectionAllButFirst }
        }
    }

    func ok() { _w.onOK(result(), scope) }

    func result() -> PageBorders? {
        guard setting != .none, !b.sides.isEmpty else { return nil }
        var r = b
        r.shadow = setting == .shadow
        return r
    }


    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func toggle(_ key: String, _ label: String, _ on: Bool, _ f: @escaping () -> Void) -> Widget {
            PKeyed(key, Chrome.textToggle(label, on, fluent) { [weak self] in self?.setState { f() } })
        }
        func label(_ s: String) -> Widget { Text(s, style: fluent.typography.body) }
        func side(_ s: PageBorders.Side) -> Widget {
            toggle("pb-side-\(s.rawValue)", s.title, b.sides.contains(s)) {
                if self.b.sides.contains(s) { self.b.sides.remove(s) } else { self.b.sides.insert(s); if self.setting == .none { self.setting = .box } }
            }
        }
        func space(_ s: PageBorders.Side) -> Widget {
            Chrome.spinner(s.title, Double(b.space[s] ?? 0), fluent, step: 1) { [weak self] v in
                self?.setState { self?.b.space[s] = min(31, Int(v.rounded())) } }
        }
        var children: [Widget] = [
            label("Setting:"), Chrome.vgap(4),
            Row(children: [toggle("pb-none", "None", setting == .none) { self.setting = .none },
                           toggle("pb-box", "Box", setting == .box) { self.setting = .box; if self.b.sides.isEmpty { self.b.sides = Set(PageBorders.Side.allCases) } },
                           toggle("pb-shadow", "Shadow", setting == .shadow) { self.setting = .shadow; if self.b.sides.isEmpty { self.b.sides = Set(PageBorders.Side.allCases) } }]),
            Chrome.vgap(8), label("Style:"), Chrome.vgap(4),
            Wrap(spacing: 4, runSpacing: 4, children: Self.styles.map { st in toggle("pb-style-\(st.0)", st.1, b.style == st.0) { self.b.style = st.0 } }),
            Chrome.vgap(8), label("Width:"), Chrome.vgap(4),
            Wrap(spacing: 4, runSpacing: 4, children: Self.widths.map { w in toggle("pb-width-\(w)", Self.widthLabel(w), b.width == w) { self.b.width = w } }),
            Chrome.vgap(8),
            Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 90, height: nil, child: label("Color:")),
                PKeyed("pb-color", Chrome.textToggle(b.color.map(ColorMath.hex) ?? "Automatic", _colorOpen, fluent) { [weak self] in
                    self?.setState { self?._colorOpen.toggle() } }),
            ]),
        ]
        if _colorOpen {
            children.append(ColorPicker(automaticLabel: "Automatic", onChoose: { [weak self] c in
                self?.setState {
                    self?.b.color = c == .automatic ? nil : c.resolved(theme: ColorMath.officeTheme)
                    self?._colorOpen = false
                }
            }, onMore: {}))
        }
        children += [
            Chrome.vgap(8), label("Sides (Preview):"), Chrome.vgap(4),
            Row(children: PageBorders.Side.allCases.map(side)),
            Chrome.vgap(8), label("Apply to:"), Chrome.vgap(4),
            Wrap(spacing: 4, runSpacing: 4, children: RichDocumentController.PageBordersScope.allCases.map { s in
                toggle("pb-scope-\(s.rawValue)", s.title, scope == s) { self.scope = s } }),
            Chrome.vgap(8), label("Options — measure from:"), Chrome.vgap(4),
            Row(children: [toggle("pb-from-page", "Edge of page", b.offsetFrom == "page") { self.b.offsetFrom = "page"; self.b.space = PageBorders.defaultSpace(from: "page") },
                           toggle("pb-from-text", "Text", b.offsetFrom == "text") { self.b.offsetFrom = "text"; self.b.space = PageBorders.defaultSpace(from: "text") }]),
            Chrome.vgap(4),
            Row(children: [space(.top), Chrome.gap(8), space(.bottom)]),
            Row(children: [space(.left), Chrome.gap(8), space(.right)]),
        ]
        return DialogShell(title: "Borders and Shading", page: Column(crossAxisAlignment: .start, children: children), okEnabled: true, width: 620,
                           onOK: { [weak self] in self?.ok() },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}

// MARK: Line numbers

final class LineNumbersDialog: StatefulWidget {
    let initial: LineNumbering?
    let onOK: (LineNumbering?) -> Void
    let onCancel: () -> Void

    init(initial: LineNumbering?, onOK: @escaping (LineNumbering?) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { LineNumbersDialogState() }
}

final class LineNumbersDialogState: State<StatefulWidget> {
    private var _w: LineNumbersDialog { widget as! LineNumbersDialog }
    var on = false
    var n = LineNumbering()

    override func initState() {
        super.initState()
        if let i = _w.initial { on = true; n = i }
    }

    func ok() { _w.onOK(on ? n : nil) }


    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let body = fluent.typography.body
        func toggle(_ key: String, _ label: String, _ isOn: Bool, _ f: @escaping () -> Void) -> Widget {
            PKeyed(key, Chrome.textToggle(label, isOn, fluent) { [weak self] in self?.setState { f() } })
        }
        var children: [Widget] = [
            PKeyed("ln-add", Checkbox(checked: on, onChanged: { [weak self] v in self?.setState { self?.on = v ?? false } },
                                      content: Text("Add line numbering", style: body))),
        ]
        if on {
            children += [
                Chrome.vgap(8),
                Chrome.spinner("Start at", Double(n.start), fluent, step: 1, unit: "", minimum: 1) { [weak self] v in
                    self?.setState { self?.n.start = Int(v.rounded()) } },
                Chrome.vgap(4),
                Row(crossAxisAlignment: .center, children: [
                    Chrome.spinner("From text", n.distance ?? 18, fluent, step: 3) { [weak self] v in self?.setState { self?.n.distance = v } },
                    Chrome.gap(8),
                    PKeyed("ln-auto", Checkbox(checked: n.distance == nil, onChanged: { [weak self] v in
                        self?.setState { self?.n.distance = (v ?? false) ? nil : 18 } }, content: Text("Auto", style: body))),
                ]),
                Chrome.vgap(4),
                Chrome.spinner("Count by", Double(n.countBy), fluent, step: 1, unit: "", minimum: 1) { [weak self] v in
                    self?.setState { self?.n.countBy = max(1, Int(v.rounded())) } },
                Chrome.vgap(8), Text("Numbering:", style: body), Chrome.vgap(4),
                Row(children: [toggle("ln-page", "Restart each page", n.restart == .newPage) { self.n.restart = .newPage },
                               toggle("ln-section", "Restart each section", n.restart == .newSection) { self.n.restart = .newSection },
                               toggle("ln-continuous", "Continuous", n.restart == .continuous) { self.n.restart = .continuous }]),
            ]
        }
        return DialogShell(title: "Line Numbers", page: Column(crossAxisAlignment: .start, children: children), okEnabled: true, width: 460,
                           onOK: { [weak self] in self?.ok() },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
