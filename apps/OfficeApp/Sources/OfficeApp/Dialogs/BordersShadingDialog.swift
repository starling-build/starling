// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-TB-2: Borders and Shading. Pick the sides, the line (style, width, colour) and the
// cell shading in one place; OK applies them to the selected cells as one undoable step.

import Flutter
import FlutterSwiftBridge
import OfficeText

/// 3 not 3.0; 0.75 as it is.
func widthLabel(_ w: Double) -> String { w == w.rounded() ? String(Int(w)) : "\(w)" }

struct BordersShadingValues: Equatable {
    enum Shade: Equatable { case unchanged, none, rgb(UInt32), theme(rgb: UInt32, attrs: String) }
    var sides: Set<CellSide> = []
    var style = "single"
    var width = 0.5
    var lineRGB: UInt32?            // nil is automatic
    var lineThemeAttrs: String?     // the theme link of the line colour (` w:themeColor="accent2" ...`), when it was picked from the theme
    var shade = Shade.unchanged

    var line: CellBorderLine {
        CellBorderLine(style: style, width: width, color: lineRGB.map { Color(Int64(0xFF000000) | Int64($0)) }, themeAttrs: lineRGB == nil ? nil : lineThemeAttrs)
    }
    var shading: Color?? {
        switch shade {
        case .unchanged: return nil
        case .none: return .some(nil)
        case .rgb(let c), .theme(let c, _): return .some(Color(Int64(0xFF000000) | Int64(c)))
        }
    }
    var shadingThemeAttrs: String? { if case .theme(_, let a) = shade { return a }; return nil }
    /// A colour picked for the line: a theme pick keeps its link to the theme slot.
    mutating func pickLine(_ choice: ColorChoice) {
        guard let rgb = choice.resolved(theme: ColorMath.officeTheme) else { lineRGB = nil; lineThemeAttrs = nil; return }
        lineRGB = rgb
        if case .theme(let slot, let mod, let off) = choice { lineThemeAttrs = WordTheme.attrs(slot: slot, lumMod: mod, lumOff: off, fill: false) } else { lineThemeAttrs = nil }
    }
    mutating func pickShading(_ choice: ColorChoice) {
        guard let rgb = choice.resolved(theme: ColorMath.officeTheme) else { shade = .none; return }
        if case .theme(let slot, let mod, let off) = choice, let a = WordTheme.attrs(slot: slot, lumMod: mod, lumOff: off, fill: true) { shade = .theme(rgb: rgb, attrs: a) } else { shade = .rgb(rgb) }
    }
    /// One undoable change per OK: borders first, then shading.
    func apply(to c: RichDocumentController) {
        if !c.isInCell {
            c.edit {
                if !sides.isEmpty { c.setParagraphBorders(sides, line) }
                if let s = shading { c.setParagraphShading(s) }
            }
            return
        }
        c.edit {
            if !sides.isEmpty { c.setCellBorders(Dictionary(uniqueKeysWithValues: sides.map { ($0, line) })) }
            if let s = shading { c.setCellShading(s, themeAttrs: shadingThemeAttrs) }
        }
    }
}

final class BordersShadingDialog: StatefulWidget {
    let onOK: (BordersShadingValues) -> Void
    let onCancel: () -> Void
    init(onOK: @escaping (BordersShadingValues) -> Void, onCancel: @escaping () -> Void) {
        self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { BordersShadingDialogState() }
}

final class BordersShadingDialogState: State<StatefulWidget> {
    private enum Target { case line, shading }
    private var _w: BordersShadingDialog { widget as! BordersShadingDialog }
    private(set) var v = BordersShadingValues()
    private var _open: Target?          // which colour panel is showing
    private var _more: Target?          // which colour "More Colors…" is editing
    private var _recent = RecentColors()

    private func choose(_ t: Target, _ choice: ColorChoice) {
        setState {
            if t == .line { v.pickLine(choice) } else { v.pickShading(choice) }
            if let rgb = choice.resolved(theme: ColorMath.officeTheme) { _recent.use(rgb) }
            _open = nil
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func toggle(_ label: String, _ on: Bool, _ f: @escaping () -> Void) -> Widget {
            Chrome.textToggle(label, on, fluent) { [weak self] in self?.setState { f() } }
        }
        func side(_ label: String, _ s: CellSide) -> Widget {
            toggle(label, v.sides.contains(s)) { if self.v.sides.contains(s) { self.v.sides.remove(s) } else { self.v.sides.insert(s) } }
        }
        func swatch(_ rgb: UInt32?) -> Widget {
            SizedBox(width: 18, height: 18, child: DecoratedBox(decoration: BoxDecoration(
                color: rgb.map { Color(Int64(0xFF000000) | Int64($0)) },
                border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1))))
        }
        func colorRow(_ label: String, _ t: Target, _ rgb: UInt32?, _ none: String) -> Widget {
            Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 120, height: nil, child: Text(label)),
                Chrome.textToggle(rgb.map(ColorMath.hex) ?? none, _open == t, fluent) { [weak self] in
                    self?.setState { self?._open = self?._open == t ? nil : t } },
                Chrome.gap(6), swatch(rgb),
            ])
        }
        func panel(_ t: Target) -> Widget {
            ColorPicker(recent: _recent.list, automaticLabel: t == .line ? "Automatic" : nil,
                        noneLabel: t == .shading ? "No Color" : nil,
                        onChoose: { [weak self] c in self?.choose(t, c) },
                        onMore: { [weak self] in self?.setState { self?._more = t } })
        }
        var shadeRGB: UInt32?
        if case .rgb(let c) = v.shade { shadeRGB = c } else if case .theme(let c, _) = v.shade { shadeRGB = c }
        let shadeNone = v.shade == .unchanged ? "Unchanged" : "No Color"
        let styles: [(String, String)] = [("single", "Single"), ("double", "Double"), ("dashed", "Dashed"), ("dotted", "Dotted"), ("none", "No line")]
        let widths = CellBorderLine.widths
        var children: [Widget] = [
            Text("Apply to"), Chrome.vgap(4),
            Row(children: [side("Top", .top), side("Bottom", .bottom), side("Left", .left), side("Right", .right),
                           side("Inside horizontal", .insideH), side("Inside vertical", .insideV)]),
            Chrome.vgap(8), Text("Line style"), Chrome.vgap(4),
            Row(children: styles.map { st in toggle(st.1, v.style == st.0) { self.v.style = st.0 } }),
            Chrome.vgap(8), Text("Width (pt)"), Chrome.vgap(4),
            Row(children: widths.map { w in toggle(widthLabel(w), v.width == w) { self.v.width = w } }),
            Chrome.vgap(8),
            colorRow("Line colour", .line, v.lineRGB, "Automatic"),
        ]
        if _open == .line { children.append(panel(.line)) }
        children.append(Chrome.vgap(4))
        children.append(colorRow("Shading", .shading, shadeRGB, shadeNone))
        if _open == .shading { children.append(panel(.shading)) }
        let dialog = DialogShell(title: "Borders and Shading", page: Column(crossAxisAlignment: .start, children: children), width: 620,
                                 onOK: { [weak self] in guard let self else { return }; self._w.onOK(self.v) },
                                 onCancel: { [weak self] in self?._w.onCancel() })
        guard let t = _more else { return dialog }
        return Stack(children: [
            dialog,
            Positioned(left: 0, top: 0, right: 0, bottom: 0, child: CustomColorDialog(
                initial: (t == .line ? v.lineRGB : shadeRGB) ?? 0,
                onOK: { [weak self] rgb in self?.setState { self?._more = nil }; self?.choose(t, .rgb(rgb)) },
                onCancel: { [weak self] in self?.setState { self?._more = nil } })),
        ])
    }
}
