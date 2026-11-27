// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-6c: Data → Consolidate. Function, a reference box with Add and a list of the references so far
// (each removable), "Use labels in" top row / left column, "Create links to source data".

import Flutter
import FlutterSwiftBridge
import Foundation

final class ConsolidateDialog: StatefulWidget {
    let controller: WorkbookController
    let onClose: () -> Void

    init(controller: WorkbookController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { ConsolidateDialogState() }
}

final class ConsolidateDialogState: State<StatefulWidget> {
    private var _w: ConsolidateDialog { widget as! ConsolidateDialog }
    let reference = TextEditingController()
    private(set) var function = ConsolidateFunction.sum
    private(set) var sources: [ConsolidateSource] = []
    private(set) var topRow = false
    private(set) var leftColumn = false
    private(set) var link = false
    private(set) var message = ""
    private var _seeded = false

    func setFunction(_ f: ConsolidateFunction) { function = f; setState {} }
    func setTop(_ on: Bool) { topRow = on; setState {} }
    func setLeft(_ on: Bool) { leftColumn = on; setState {} }
    func setLink(_ on: Bool) { link = on; setState {} }
    func remove(_ i: Int) { if i < sources.count { sources.remove(at: i); message = ""; setState {} } }

    /// Take what is in the reference box into the list. False (with a message) when it is not a reference.
    @discardableResult func add() -> Bool {
        let t = reference.text.trimmingWhitespace()
        if t.isEmpty { return true }
        guard let s = _w.controller.parseConsolidateReference(t) else { message = ConsolidateProblem.badReference(t).message; setState {}; return false }
        if !sources.contains(s) { sources.append(s) }
        reference.text = ""; message = ""; setState {}
        return true
    }

    func apply() {
        guard add() else { return }
        let c = _w.controller
        let out = c.consolidate(sources, function: function, topRow: topRow, leftColumn: leftColumn, link: link, at: c.active)
        if let p = out.problem { message = p.message; setState {}; return }
        if let n = out.cells { c.onCommand?(.status("Consolidated \(n) cell\(n == 1 ? "" : "s") at \(c.active.a1). Undo brings back what was there.")) }
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        if !_seeded {
            _seeded = true
            let c = _w.controller
            reference.text = c.consolidateReferenceText(ConsolidateSource(sheet: c.activeSheet, range: c.selection))
        }
        let fluent = FluentTheme.of(context)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        var rows: [Widget] = [
            Text("Function:", style: fluent.typography.body), gap(4),
            SizedBox(width: 280, height: nil, child: ComboBox<Int>(
                key: ValueKey("cons-function"), value: function.rawValue,
                items: ConsolidateFunction.allCases.map { ComboBoxItem<Int>(value: $0.rawValue, child: Text($0.label)) },
                onChanged: { [weak self] v in if let v, let f = ConsolidateFunction(rawValue: v) { self?.setFunction(f) } })),
            gap(8),
            Text("Reference:", style: fluent.typography.body), gap(4),
            Row(children: [
                SizedBox(width: 280, height: Chrome.touchFieldHeight, child: FluentTextBox(key: ValueKey("cons-ref"), controller: reference, placeholderText: "Sheet2!A1:C10")),
                SizedBox(width: 8, height: nil, child: nil),
                Button(key: ValueKey("cons-add"), onPressed: { [weak self] in self?.add() }, child: Text("Add")),
            ]),
            gap(8),
            Text("All references:", style: fluent.typography.body), gap(4),
        ]
        for (i, s) in sources.enumerated() {
            rows.append(Row(children: [
                SizedBox(width: 280, height: nil, child: Text(_w.controller.consolidateReferenceText(s))),
                Button(key: ValueKey("cons-delete-\(i)"), onPressed: { [weak self] in self?.remove(i) }, child: Text("Delete")),
            ]))
            rows.append(gap(2))
        }
        rows.append(gap(6))
        rows.append(Text("Use labels in:", style: fluent.typography.body))
        rows.append(gap(4))
        rows.append(Checkbox(key: ValueKey("cons-top"), checked: topRow, onChanged: { [weak self] v in self?.setTop(v ?? false) }, content: Text("Top row")))
        rows.append(Checkbox(key: ValueKey("cons-left"), checked: leftColumn, onChanged: { [weak self] v in self?.setLeft(v ?? false) }, content: Text("Left column")))
        rows.append(gap(4))
        rows.append(Checkbox(key: ValueKey("cons-link"), checked: link, onChanged: { [weak self] v in self?.setLink(v ?? false) }, content: Text("Create links to source data")))
        rows.append(gap(6))
        rows.append(Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C))))
        return DialogShell(title: "Consolidate", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                           okLabel: "OK", cancelLabel: "Close", width: 460,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
