// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-LI-1: "Adjust List Indents" (a list item's right-click): the caret level's number
// position, text indent and what follows the number. OK applies them to that level of the
// list as one undoable step (`adjustListIndents`).

import Flutter
import FlutterSwiftBridge
import OfficeText

private final class AIKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}

final class AdjustListIndentsDialog: StatefulWidget {
    let numberAt: Double
    let textAt: Double
    let follow: String
    let unit: LengthUnit
    let onOK: (Double, Double, String) -> Void
    let onCancel: () -> Void
    init(numberAt: Double, textAt: Double, follow: String, unit: LengthUnit = .inch,
         onOK: @escaping (Double, Double, String) -> Void, onCancel: @escaping () -> Void) {
        self.numberAt = numberAt; self.textAt = textAt; self.follow = follow; self.unit = unit
        self.onOK = onOK; self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { AdjustListIndentsDialogState() }
}

final class AdjustListIndentsDialogState: State<StatefulWidget> {
    private var _w: AdjustListIndentsDialog { widget as! AdjustListIndentsDialog }
    private(set) var numberAt = 0.0
    private(set) var textAt = 0.0
    private(set) var follow = "tab"

    override func initState() {
        super.initState()
        numberAt = _w.numberAt; textAt = _w.textAt; follow = _w.follow
    }

    func setNumberAt(_ v: Double) { setState { numberAt = v } }
    func setTextAt(_ v: Double) { setState { textAt = v } }
    func setFollow(_ v: String) { setState { follow = v } }
    func ok() { _w.onOK(numberAt, textAt, follow) }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func row(_ label: String, _ child: Widget) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 8), child: Row(crossAxisAlignment: .center, children: [
                SizedBox(width: 130, height: nil, child: Text(label)), child,
            ]))
        }
        let rows: [Widget] = [
            row("Number position", AIKeyed("ai-number", UnitSpinner(points: numberAt, unit: _w.unit, width: 110) { [weak self] v in self?.setNumberAt(v) })),
            row("Text indent", AIKeyed("ai-text", UnitSpinner(points: textAt, unit: _w.unit, width: 110) { [weak self] v in self?.setTextAt(v) })),
            row("Follow number with", Row(children: MultilevelListDialogState.follows.map { fo in
                AIKeyed("ai-follow-\(fo.id)", Chrome.textToggle(fo.title, follow == fo.id, fluent) { [weak self] in self?.setFollow(fo.id) })
            })),
        ]
        return DialogShell(title: "Adjust List Indents",
                           page: Column(crossAxisAlignment: .start, children: rows),
                           okEnabled: true, width: 460,
                           onOK: { [weak self] in self?.ok() },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
