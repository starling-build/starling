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
    var sides: Set<CellSide> = []
    var style = "single"
    var width = 0.5
    var colorText = ""      // RRGGBB; blank is automatic
    var shadingText = ""    // RRGGBB; blank leaves the shading alone
    var clearShading = false

    var line: CellBorderLine {
        CellBorderLine(style: style, width: width, color: ColorMath.parseHex(colorText).map { Color(Int64(0xFF000000) | Int64($0)) })
    }
    var shading: Color?? {
        if clearShading { return .some(nil) }
        return ColorMath.parseHex(shadingText).map { .some(Color(Int64(0xFF000000) | Int64($0))) }
    }
    /// One undoable change per OK: borders first, then shading.
    func apply(to c: RichDocumentController) {
        c.edit {
            if !sides.isEmpty { c.setCellBorders(Dictionary(uniqueKeysWithValues: sides.map { ($0, line) })) }
            if let s = shading { c.setCellShading(s) }
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
    private var _w: BordersShadingDialog { widget as! BordersShadingDialog }
    private(set) var v = BordersShadingValues()
    private let _color = TextEditingController()
    private let _shading = TextEditingController()

    func commit() { v.colorText = _color.text; v.shadingText = _shading.text }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func toggle(_ label: String, _ on: Bool, _ f: @escaping () -> Void) -> Widget {
            Chrome.textToggle(label, on, fluent) { [weak self] in self?.setState { f() } }
        }
        func side(_ label: String, _ s: CellSide) -> Widget {
            toggle(label, v.sides.contains(s)) { if self.v.sides.contains(s) { self.v.sides.remove(s) } else { self.v.sides.insert(s) } }
        }
        func box(_ label: String, _ c: TextEditingController) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 170, height: nil, child: Text(label)),
                SizedBox(width: 90, height: 30, child: FluentTextBox(
                    controller: c, onSubmitted: { [weak self] _ in self?.commit() },
                    onFocusChanged: { [weak self] f in if !f { self?.commit() } })),
            ]))
        }
        let styles: [(String, String)] = [("single", "Single"), ("double", "Double"), ("dashed", "Dashed"), ("dotted", "Dotted"), ("none", "No line")]
        let widths = CellBorderLine.widths
        let page = Column(crossAxisAlignment: .start, children: [
            Text("Apply to"), Chrome.vgap(4),
            Row(children: [side("Top", .top), side("Bottom", .bottom), side("Left", .left), side("Right", .right),
                           side("Inside horizontal", .insideH), side("Inside vertical", .insideV)]),
            Chrome.vgap(8), Text("Line style"), Chrome.vgap(4),
            Row(children: styles.map { st in toggle(st.1, v.style == st.0) { self.v.style = st.0 } }),
            Chrome.vgap(8), Text("Width (pt)"), Chrome.vgap(4),
            Row(children: widths.map { w in toggle(widthLabel(w), v.width == w) { self.v.width = w } }),
            Chrome.vgap(8),
            box("Line colour (RRGGBB, blank is automatic)", _color),
            box("Shading (RRGGBB)", _shading),
            toggle("Remove shading", v.clearShading) { self.v.clearShading.toggle() },
        ])
        return DialogShell(title: "Borders and Shading", page: page, width: 620,
                           onOK: { [weak self] in guard let self else { return }; self.commit(); self._w.onOK(self.v) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
