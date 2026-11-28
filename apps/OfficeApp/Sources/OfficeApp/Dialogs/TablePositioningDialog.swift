// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-TB-5: Table Properties > Text wrapping Around > Positioning: where a floating table stands (horizontal and
// vertical place and what each is measured from), its distance from the text, Move with text and Allow overlap.

import Flutter
import FlutterSwiftBridge
import OfficeText

final class TablePositioningDialog: StatefulWidget {
    let initial: TablePosition
    let unit: LengthUnit
    let onOK: (TablePosition) -> Void
    let onCancel: () -> Void
    init(initial: TablePosition, unit: LengthUnit = .inch, onOK: @escaping (TablePosition) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial; self.unit = unit; self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { TablePositioningDialogState() }
}

final class TablePositioningDialogState: State<StatefulWidget> {
    private var _w: TablePositioningDialog { widget as! TablePositioningDialog }
    private(set) var v = TablePosition()

    override func initState() {
        super.initState()
        v = _w.initial
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let unit = _w.unit
        func choice(_ id: String, _ label: String, _ on: Bool, _ action: @escaping () -> Void) -> Widget {
            PKeyed(id, Chrome.textToggle(label, on, fluent, action: action))
        }
        func row(_ label: String, _ items: [Widget]) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children:
                [SizedBox(width: 110, height: nil, child: Text(label))] + items))
        }
        func spin(_ id: String, _ pts: Double, min: Double = 0, _ set: @escaping (Double) -> Void) -> Widget {
            PKeyed(id, UnitSpinner(points: pts, unit: unit, min: min, max: 1584, width: 90) { [weak self] n in self?.setState { set(n) } })
        }
        // Word's Position box is a list (Left, Center, Right, Inside, Outside) that also takes a distance: here the
        // aligns are toggles and the spinner is the distance (typing one clears the align).
        let hAligns = ["left", "center", "right", "inside", "outside"]
        let vAligns = ["top", "center", "bottom", "inside", "outside"]
        let hFrom: [(String, TablePosition.HorizontalFrom)] = [("Column", .column), ("Margin", .margin), ("Page", .page)]
        let vFrom: [(String, TablePosition.VerticalFrom)] = [("Paragraph", .paragraph), ("Margin", .margin), ("Page", .page)]
        let page = Column(crossAxisAlignment: .start, children: [
            Text("Horizontal"),
            row("Position", hAligns.map { a in choice("tpos-h-\(a)", a.prefix(1).uppercased() + a.dropFirst(), v.horizontalAlign == a) { [weak self] in
                self?.setState { self?.v.horizontalAlign = self?.v.horizontalAlign == a ? nil : a } } }),
            row("", [spin("tpos-x", v.x, min: -1584) { [weak self] n in self?.v.x = n; self?.v.horizontalAlign = nil }]),
            row("Relative to", hFrom.map { t, f in choice("tpos-hfrom-\(f.rawValue)", t, v.horizontalFrom == f) { [weak self] in
                self?.setState { self?.v.horizontalFrom = f } } }),
            Text("Vertical"),
            row("Position", vAligns.map { a in choice("tpos-v-\(a)", a.prefix(1).uppercased() + a.dropFirst(), v.verticalAlign == a) { [weak self] in
                self?.setState { self?.v.verticalAlign = self?.v.verticalAlign == a ? nil : a } } }),
            row("", [spin("tpos-y", v.y, min: -1584) { [weak self] n in self?.v.y = n; self?.v.verticalAlign = nil }]),
            row("Relative to", vFrom.map { t, f in choice("tpos-vfrom-\(f.rawValue)", t, v.verticalFrom == f) { [weak self] in
                self?.setState { self?.v.verticalFrom = f } } }),
            Text("Distance from surrounding text"),
            row("Top", [spin("tpos-top", v.top) { [weak self] n in self?.v.top = n }]),
            row("Bottom", [spin("tpos-bottom", v.bottom) { [weak self] n in self?.v.bottom = n }]),
            row("Left", [spin("tpos-left", v.left) { [weak self] n in self?.v.left = n }]),
            row("Right", [spin("tpos-right", v.right) { [weak self] n in self?.v.right = n }]),
            row("Options", [
                choice("tpos-move", "Move with text", v.movesWithText) { [weak self] in self?.setState { self?.v.movesWithText.toggle() } },
                choice("tpos-overlap", "Allow overlap", v.allowOverlap) { [weak self] in self?.setState { self?.v.allowOverlap.toggle() } },
            ]),
        ])
        return DialogShell(title: "Table Positioning", page: page, width: 560,
                           onOK: { [weak self] in guard let self else { return }; self._w.onOK(self.v) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
