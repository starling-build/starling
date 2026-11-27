// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CF-1: Manage Rules. Lists every conditional-format rule of the sheet by
// priority. Pick one to move it up or down, delete it, or switch Stop If True.
// Each change is one undo step, made by the controller.

import Flutter
import FlutterSwiftBridge
import Foundation

final class ManageRulesDialog: StatefulWidget {
    let controller: WorkbookController
    let onClose: () -> Void

    init(controller: WorkbookController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { ManageRulesDialogState() }
}

final class ManageRulesDialogState: State<StatefulWidget> {
    private var _w: ManageRulesDialog { widget as! ManageRulesDialog }
    /// The picked rule's place, kept by element and occurrence so it survives a reorder.
    private var picked: (Int, Int, Bool)?

    private func _row() -> CFRuleRow? {
        guard let p = picked else { return nil }
        return _w.controller.conditionalRuleRows().first { $0.element == p.0 && $0.occurrence == p.1 && $0.ext == p.2 }
    }

    func pick(_ r: CFRuleRow) { picked = (r.element, r.occurrence, r.ext); setState {} }

    func moveUp(_ up: Bool) {
        guard let r = _row() else { return }
        _w.controller.moveConditionalRule(r, up: up)
        setState {}
    }

    func toggleStop() {
        guard let r = _row() else { return }
        _w.controller.setConditionalStopIfTrue(r, !r.stopIfTrue)
        setState {}
    }

    /// X-DA-3c: the rule being edited; the form stands in for the list until it closes.
    private(set) var editing: CFRuleRow?
    func editPicked() { editing = _row(); setState {} }

    func deletePicked() {
        guard let r = _row() else { return }
        _w.controller.deleteConditionalRule(r)
        picked = nil
        setState {}
    }

    override func build(_ context: any BuildContext) -> Widget {
        if let e = editing {
            return ConditionalFormatDialog(controller: _w.controller, editing: e, onClose: { [weak self] in
                self?.editing = nil; self?.setState {} })
        }
        let fluent = FluentTheme.of(context)
        let rows = _w.controller.conditionalRuleRows()
        let cur = _row()
        let items: [Widget] = rows.map { r in
            let on = picked.map { $0.0 == r.element && $0.1 == r.occurrence && $0.2 == r.ext } ?? false
            return KeyboardRow(label: r.summary, activate: { [weak self] in self?.pick(r) }, child: GestureDetector(onTap: { [weak self] in self?.pick(r) }, behavior: .opaque, child: ColoredBox(
                color: on ? fluent.resources.subtleFillColorSecondary : Color(0x00000000),
                child: Padding(padding: EdgeInsets(left: 8, top: 4, right: 8, bottom: 4), child: Row(children: [
                    Expanded(child: Text(r.summary, style: on ? fluent.typography.bodyStrong : fluent.typography.body)),
                    SizedBox(width: 130, height: nil, child: Text(r.applies, style: fluent.typography.caption)),
                    SizedBox(width: 60, height: nil, child: Text(r.stopIfTrue ? "Stop" : "", style: fluent.typography.caption)),
                ])))))
        }
        let list = SizedBox(width: nil, height: 200, child: SingleChildScrollView(child: Column(
            crossAxisAlignment: .stretch,
            children: items.isEmpty ? [Padding(padding: EdgeInsets(all: 8), child: Text("No rules on this sheet", style: fluent.typography.caption))] : items)))
        let page = Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: [
            Text("Rules run from the top. Applies to / Stop If True", style: fluent.typography.caption),
            SizedBox(width: nil, height: 6, child: nil),
            list,
            SizedBox(width: nil, height: 10, child: nil),
            Row(children: [
                Button(key: ValueKey("cf-rule-edit"), onPressed: cur != nil ? { [weak self] in self?.editPicked() } : nil, child: Text("Edit Rule…")),
                SizedBox(width: 8, height: nil, child: nil),
                Button(key: ValueKey("cf-rule-up"), onPressed: cur != nil ? { [weak self] in self?.moveUp(true) } : nil, child: Text("Move Up")),
                SizedBox(width: 8, height: nil, child: nil),
                Button(key: ValueKey("cf-rule-down"), onPressed: cur != nil ? { [weak self] in self?.moveUp(false) } : nil, child: Text("Move Down")),
                SizedBox(width: 8, height: nil, child: nil),
                Button(key: ValueKey("cf-rule-stop"), onPressed: cur != nil ? { [weak self] in self?.toggleStop() } : nil,
                       child: Text(cur?.stopIfTrue == true ? "Stop If True: On" : "Stop If True: Off")),
                SizedBox(width: 8, height: nil, child: nil),
                Button(key: ValueKey("cf-rule-delete"), onPressed: cur != nil ? { [weak self] in self?.deletePicked() } : nil, child: Text("Delete")),
            ]),
        ])
        return DialogShell(title: "Manage Rules", page: page, okLabel: "OK", cancelLabel: "Close", okEnabled: true, width: 640,
                           onOK: _w.onClose, onCancel: _w.onClose)
    }
}
