// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-6c: Data → What-If Analysis → Goal Seek. Set cell, To value, By changing cell; a miss shows in red and
// the dialog stays, a hit closes it and reports the answer in the status bar.

import Flutter
import FlutterSwiftBridge
import Foundation

final class GoalSeekDialog: StatefulWidget {
    let controller: WorkbookController
    let onClose: () -> Void
    init(controller: WorkbookController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { GoalSeekDialogState() }
}

final class GoalSeekDialogState: State<StatefulWidget> {
    private var _w: GoalSeekDialog { widget as! GoalSeekDialog }
    let setCell = TextEditingController()
    let toValue = TextEditingController()
    let changing = TextEditingController()
    private(set) var message = ""
    private var _seeded = false

    func apply() {
        let c = _w.controller
        guard let s = CellAddress(setCell.text.trimmingWhitespace().replacingAll("$", with: "").uppercased()) else { message = GoalSeekProblem.badSetCell.message; setState {}; return }
        guard let ch = CellAddress(changing.text.trimmingWhitespace().replacingAll("$", with: "").uppercased()) else { message = GoalSeekProblem.badChangingCell.message; setState {}; return }
        guard let target = Double(toValue.text.trimmingWhitespace()) else { message = GoalSeekProblem.badTarget.message; setState {}; return }
        let out = c.goalSeek(set: s, to: target, changing: ch)
        if let p = out.problem { message = p.message; setState {}; return }
        if let r = out.result { c.onCommand?(.status("Goal Seeking found a solution: \(r.value)")) }
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        if !_seeded { _seeded = true; setCell.text = _w.controller.active.a1 }
        let fluent = FluentTheme.of(context)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        func line(_ label: String, _ id: String, _ c: TextEditingController) -> Widget {
            Row(children: [
                SizedBox(width: 130, height: nil, child: Text(label)),
                SizedBox(width: 160, height: Chrome.touchFieldHeight, child: FluentTextBox(key: ValueKey(id), controller: c, placeholderText: "")),
            ])
        }
        let rows: [Widget] = [
            line("Set cell:", "goalseek-set", setCell), gap(8),
            line("To value:", "goalseek-value", toValue), gap(8),
            line("By changing cell:", "goalseek-changing", changing), gap(8),
            Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C))),
        ]
        return DialogShell(title: "Goal Seek", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                           okLabel: "OK", cancelLabel: "Cancel", width: 400,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
