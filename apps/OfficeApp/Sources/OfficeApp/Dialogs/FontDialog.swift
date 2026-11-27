// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-CH-2: the Font dialog. Font page: face, size, the style switches (bold,
// italic, underline, strike, double strike, super/subscript, small caps, all
// caps, hidden). Advanced page: letter spacing, scale, raise/lower, kerning.
// OK applies it all as one undoable step (`setCharFormat`).

import Flutter
import FlutterSwiftBridge
import OfficeText

private final class FKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}

final class FontDialog: StatefulWidget {
    let initial: RichDocumentController.CharFormat
    let onOK: (RichDocumentController.CharFormat) -> Void
    let onCancel: () -> Void
    init(initial: RichDocumentController.CharFormat,
         onOK: @escaping (RichDocumentController.CharFormat) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { FontDialogState() }
}

final class FontDialogState: State<StatefulWidget> {
    private var _w: FontDialog { widget as! FontDialog }
    private(set) var v = RichDocumentController.CharFormat()
    private let _family = TextEditingController()
    private let _scale = TextEditingController()

    override func initState() {
        super.initState()
        v = _w.initial
        _family.text = v.family ?? ""
        _scale.text = String(Int(((v.scale ?? 1) * 100).rounded()))
    }

    /// The format the dialog would apply now: the typed face and scale folded in.
    var result: RichDocumentController.CharFormat {
        var f = v
        let face = _family.text.trimmingWhitespace()
        f.family = face.isEmpty ? nil : face
        if let p = Double(_scale.text.trimmingWhitespace()), p >= 1, p <= 600 { f.scale = p / 100 }
        return f
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func toggle(_ id: String, _ label: String, _ on: Bool, _ set: @escaping (inout RichDocumentController.CharFormat) -> Void) -> Widget {
            FKeyed(id, Chrome.textToggle(label, on, fluent) { [weak self] in self?.setState { if let s = self { set(&s.v) } } })
        }
        func row(_ label: String, _ items: [Widget]) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children:
                [SizedBox(width: 110, height: nil, child: Text(label))] + items))
        }
        func spin(_ id: String, _ label: String, _ pts: Double, _ lo: Double, _ hi: Double,
                  _ set: @escaping (Double) -> Void) -> Widget {
            row(label, [FKeyed(id, UnitSpinner(points: pts, unit: .pt, min: lo, max: hi, width: 90) { [weak self] n in
                self?.setState { set(n) } })])
        }
        let fontPage = Column(crossAxisAlignment: .start, children: [
            row("Font", [SizedBox(width: 200, height: Chrome.fieldHeight, child: FKeyed("ft-family", FluentTextBox(controller: _family)))]),
            spin("ft-size", "Size (pt)", v.size ?? 11, 1, 1638) { [weak self] n in self?.v.size = n },
            row("Style", [
                toggle("ft-bold", "Bold", v.bold) { $0.bold.toggle() },
                toggle("ft-italic", "Italic", v.italic) { $0.italic.toggle() },
                toggle("ft-underline", "Underline", v.underline) { $0.underline.toggle() },
            ]),
            row("Effects", [
                toggle("ft-strike", "Strikethrough", v.strikethrough) { $0.strikethrough.toggle(); if $0.strikethrough { $0.doubleStrike = false } },
                toggle("ft-double", "Double strike", v.doubleStrike) { $0.doubleStrike.toggle(); if $0.doubleStrike { $0.strikethrough = false } },
            ]),
            row("", [
                toggle("ft-super", "Superscript", v.script == .superscript) { $0.script = $0.script == .superscript ? .normal : .superscript },
                toggle("ft-sub", "Subscript", v.script == .subscript) { $0.script = $0.script == .subscript ? .normal : .subscript },
            ]),
            row("", [
                toggle("ft-smallcaps", "Small caps", v.smallCaps) { $0.smallCaps.toggle(); if $0.smallCaps { $0.caps = false } },
                toggle("ft-caps", "All caps", v.caps) { $0.caps.toggle(); if $0.caps { $0.smallCaps = false } },
                toggle("ft-hidden", "Hidden", v.hidden) { $0.hidden.toggle() },
            ]),
        ])
        let advancedPage = Column(crossAxisAlignment: .start, children: [
            spin("ft-spacing", "Spacing (pt)", v.spacing ?? 0, -100, 100) { [weak self] n in self?.v.spacing = n == 0 ? nil : n },
            row("Scale (%)", [SizedBox(width: 90, height: Chrome.fieldHeight, child: FKeyed("ft-scale", FluentTextBox(controller: _scale)))]),
            spin("ft-raised", "Position (pt)", v.raised ?? 0, -1584, 1584) { [weak self] n in self?.v.raised = n == 0 ? nil : n },
            row("Kerning", [
                toggle("ft-kern", "Kern from size", v.kerningFrom != nil) { $0.kerningFrom = $0.kerningFrom == nil ? ($0.size ?? 11) : nil },
            ]),
            v.kerningFrom == nil ? Chrome.gap(0) : spin("ft-kern-size", "Points and above", v.kerningFrom ?? 11, 1, 1638) { [weak self] n in self?.v.kerningFrom = n },
        ])
        return DialogShell(title: "Font", tabs: [DialogTab(title: "Font", page: fontPage), DialogTab(title: "Advanced", page: advancedPage)],
                           width: 480,
                           onOK: { [weak self] in guard let self else { return }; self._w.onOK(self.result) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
