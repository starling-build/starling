// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Table Layout → Cell Margins → Custom Margins: PowerPoint's Cell Text Layout dialog, its Internal margin boxes. Left,
// Right, Top and Bottom in inches (PowerPoint writes 0.1" and takes a bare number too) for the chosen cells.

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

final class CellMarginsDialog: StatefulWidget {
    /// The caret cell's margins, in points.
    let margins: EdgeInsets
    let onApply: (EdgeInsets) -> Void
    let onCancel: () -> Void

    init(margins: EdgeInsets, onApply: @escaping (EdgeInsets) -> Void, onCancel: @escaping () -> Void) {
        self.margins = margins
        self.onApply = onApply
        self.onCancel = onCancel
        super.init()
    }

    override func createState() -> State<StatefulWidget> { CellMarginsDialogState() }
}

final class CellMarginsDialogState: State<StatefulWidget> {
    /// What a margin may be, in inches.
    static let range = 0.0 ... 20.0

    private var _w: CellMarginsDialog { widget as! CellMarginsDialog }
    /// Left, right, top, bottom: PowerPoint's order.
    private let _boxes = [TextEditingController(), TextEditingController(), TextEditingController(), TextEditingController()]
    static let labels = ["Left", "Right", "Top", "Bottom"]

    /// Points as PowerPoint shows inches: 7.2 pt is 0.1".
    static func inches(_ points: Double) -> String {
        let r = (points / 72 * 100).rounded() / 100
        return (r == r.rounded() ? String(Int(r)) : String(r)) + "\""
    }

    /// A typed margin ("0.1", "0.1\"" or "0.1 in") in points, or nil when it is not a number from 0 to 20 inches.
    static func parse(_ s: String) -> Double? {
        var t = String(s.filter { $0 != " " })
        if t.hasSuffix("\"") { t.removeLast() } else if t.hasSuffix("in") { t.removeLast(2) }
        guard let v = Double(t), range.contains(v) else { return nil }
        return v * 72
    }

    override func initState() {
        super.initState()
        let m = _w.margins
        for (box, v) in zip(_boxes, [m.left, m.right, m.top, m.bottom]) { box.text = Self.inches(v) }
    }

    override func dispose() {
        for b in _boxes { b.dispose() }
        super.dispose()
    }

    private func _typed() -> EdgeInsets? {
        let v = _boxes.map { Self.parse($0.text) }
        guard let l = v[0], let r = v[1], let t = v[2], let b = v[3] else { return nil }
        return EdgeInsets(left: l, top: t, right: r, bottom: b)
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        func box(_ i: Int) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(children: [
                SizedBox(width: 60, height: nil, child: Text("\(Self.labels[i]):", style: caption)),
                SizedBox(width: 90, height: 30, child: PKeyed("cellmargins.\(Self.labels[i].lowercased())",
                    FluentTextBox(controller: _boxes[i], onChanged: { [weak self] _ in self?.setState {} }))),
            ]))
        }
        let ok = _typed() != nil
        let page = Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
            Text("Internal margin", style: caption), SizedBox(width: nil, height: 8, child: nil),
            Row(crossAxisAlignment: .start, children: [
                Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [box(0), box(1)]),
                SizedBox(width: 16, height: nil, child: nil),
                Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [box(2), box(3)]),
            ]),
            ok ? SizedBox(width: nil, height: 0, child: nil)
               : Text("Enter a margin from 0 to 20 inches.", style: caption),
        ])
        return DialogShell(title: "Cell Text Layout", page: page, okEnabled: ok, width: 380,
                           onOK: { [weak self] in
                               guard let self, let m = self._typed() else { return }
                               self._w.onApply(m)
                           },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
