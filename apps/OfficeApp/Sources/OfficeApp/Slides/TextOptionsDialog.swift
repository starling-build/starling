// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Home → Drawing → Text Options (S-TX-2): where the text sits in the shape and how it
// flows. One page on the shared DialogShell (Enter = OK, Esc = Cancel). Margins are in points.

import Flutter
import OfficeText
import FlutterSwiftBridge

final class TextOptionsDialog: StatefulWidget {
    let initial: DeckController.TextOptions
    let onApply: (DeckController.TextOptions) -> Void
    let onCancel: () -> Void

    init(initial: DeckController.TextOptions, onApply: @escaping (DeckController.TextOptions) -> Void,
         onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onApply = onApply
        self.onCancel = onCancel
        super.init()
    }

    override func createState() -> State<StatefulWidget> { TextOptionsDialogState() }
}

final class TextOptionsDialogState: State<StatefulWidget> {
    private var _w: TextOptionsDialog { widget as! TextOptionsDialog }
    private var _o = DeckController.TextOptions()
    private let _left = TextEditingController(), _top = TextEditingController()
    private let _right = TextEditingController(), _bottom = TextEditingController()
    private let _cols = TextEditingController(), _gap = TextEditingController()

    private static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(Double((v * 100).rounded()) / 100)
    }

    override func initState() {
        super.initState()
        _o = _w.initial
        _left.text = Self.fmt(_o.insets.left); _top.text = Self.fmt(_o.insets.top)
        _right.text = Self.fmt(_o.insets.right); _bottom.text = Self.fmt(_o.insets.bottom)
        _cols.text = String(_o.columns); _gap.text = Self.fmt(_o.columnGap)
    }

    override func dispose() {
        for c in [_left, _top, _right, _bottom, _cols, _gap] { c.dispose() }
        super.dispose()
    }

    /// The draft with the typed numbers applied; a field that is not a number keeps its old value.
    private func _result() -> DeckController.TextOptions {
        var o = _o
        func num(_ c: TextEditingController, _ old: Double) -> Double {
            guard let v = Double(String(c.text.filter { $0 != " " })), v >= 0, v < 1000 else { return old }
            return v
        }
        o.insets = EdgeInsets(left: num(_left, o.insets.left), top: num(_top, o.insets.top),
                              right: num(_right, o.insets.right), bottom: num(_bottom, o.insets.bottom))
        o.columns = max(1, min(16, Int(num(_cols, Double(o.columns)))))
        o.columnGap = num(_gap, o.columnGap)
        return o
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        func gap(_ h: Double) -> Widget { SizedBox(width: nil, height: h, child: nil) }
        func radio<T: Equatable>(_ id: String, _ label: String, _ v: T, _ cur: T, _ set: @escaping (T) -> Void) -> Widget {
            RadioButton<T>(key: ValueKey(id), value: v, groupValue: cur,
                           onChanged: { [weak self] _ in self?.setState { set(v) } }, content: Text(label))
        }
        func field(_ id: String, _ label: String, _ c: TextEditingController) -> Widget {
            Row(children: [
                SizedBox(width: 60, height: nil, child: Text(label, style: caption)),
                SizedBox(key: ValueKey(id), width: 64, height: Chrome.fieldHeight, child: FluentTextBox(controller: c)),
                SizedBox(width: 12, height: nil, child: nil),
            ])
        }
        func group(_ title: String, _ kids: [Widget]) -> Widget {
            Column(crossAxisAlignment: .start, children: [Text(title, style: caption), gap(4)] + kids + [gap(10)])
        }
        let page = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
            group("Vertical position", [Row(children: [
                radio("text-anchor-top", "Top", TextAnchor.top, _o.anchor) { self._o.anchor = $0 },
                SizedBox(width: 12, height: nil, child: nil),
                radio("text-anchor-middle", "Middle", TextAnchor.middle, _o.anchor) { self._o.anchor = $0 },
                SizedBox(width: 12, height: nil, child: nil),
                radio("text-anchor-bottom", "Bottom", TextAnchor.bottom, _o.anchor) { self._o.anchor = $0 },
            ])]),
            group("Text direction", [Row(children: [
                radio("text-dir-horizontal", "Horizontal", DeckController.TextOptions.Direction.horizontal, _o.direction) { self._o.direction = $0 },
                SizedBox(width: 12, height: nil, child: nil),
                radio("text-dir-rotate90", "Rotate 90°", .rotate90, _o.direction) { self._o.direction = $0 },
                SizedBox(width: 12, height: nil, child: nil),
                radio("text-dir-rotate270", "Rotate 270°", .rotate270, _o.direction) { self._o.direction = $0 },
                SizedBox(width: 12, height: nil, child: nil),
                radio("text-dir-stacked", "Stacked", .stacked, _o.direction) { self._o.direction = $0 },
            ])]),
            group("Autofit", [Row(children: [
                radio("text-fit-none", "Do not autofit", DeckController.TextOptions.Fit.none, _o.fit) { self._o.fit = $0 },
                SizedBox(width: 12, height: nil, child: nil),
                radio("text-fit-shrink", "Shrink text on overflow", .shrink, _o.fit) { self._o.fit = $0 },
                SizedBox(width: 12, height: nil, child: nil),
                radio("text-fit-resize", "Resize shape to fit text", .resize, _o.fit) { self._o.fit = $0 },
            ])]),
            Checkbox(key: ValueKey("text-wrap"), checked: _o.wrap,
                     onChanged: { [weak self] v in self?.setState { self?._o.wrap = v ?? false } },
                     content: Text("Wrap text in shape")),
            gap(10),
            group("Margins (pt)", [Row(children: [
                field("text-margin-left", "Left", _left), field("text-margin-top", "Top", _top),
            ]), gap(6), Row(children: [
                field("text-margin-right", "Right", _right), field("text-margin-bottom", "Bottom", _bottom),
            ])]),
            group("Columns", [Row(children: [
                field("text-columns", "Number", _cols), field("text-column-gap", "Spacing", _gap),
            ])]),
        ])
        return DialogShell(title: "Text Options", page: page, width: 520,
                           onOK: { [weak self] in guard let self else { return }; self._w.onApply(self._result()) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
