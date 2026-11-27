// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-6c: the Scenario Manager. One dialog with four pages: the list (Add, Edit, Delete, Show,
// Summary), the definition (name, changing cells, comment), the values for those cells, and the
// summary's result cells.

import Flutter
import FlutterSwiftBridge
import Foundation

final class ScenarioDialog: StatefulWidget {
    let controller: WorkbookController
    let onClose: () -> Void
    init(controller: WorkbookController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        super.init()
    }
    override func createState() -> State<StatefulWidget> { ScenarioDialogState() }
}

final class ScenarioDialogState: State<StatefulWidget> {
    enum Page { case list, define, values, summary }
    private var _w: ScenarioDialog { widget as! ScenarioDialog }
    let name = TextEditingController()
    let changing = TextEditingController()
    let comment = TextEditingController()
    let results = TextEditingController()
    private(set) var page = Page.list
    private(set) var selected: String?
    private(set) var message = ""
    private(set) var editing: String?
    private(set) var cells: [CellAddress] = []
    private(set) var valueBoxes: [TextEditingController] = []

    func select(_ n: String) { selected = n; message = ""; setState {} }
    func back() { page = .list; message = ""; setState {} }

    func startAdd() {
        editing = nil
        name.text = ""; comment.text = ""
        let sel = _w.controller.selection
        changing.text = sel.a1
        page = .define; message = ""; setState {}
    }

    func startEdit() {
        guard let n = selected, let s = _w.controller.scenarios().first(where: { $0.name == n }) else { message = "Pick a scenario first."; setState {}; return }
        editing = n
        name.text = s.name; comment.text = s.comment
        changing.text = s.cells.map(\.ref).joined(separator: ",")
        page = .define; message = ""; setState {}
    }

    func next() {
        let (list, bad) = Scenarios.cells(changing.text)
        if let bad { message = ScenarioProblem.badCell(bad).message; setState {}; return }
        if list.isEmpty { message = ScenarioProblem.noCells.message; setState {}; return }
        if name.text.trimmingWhitespace().isEmpty { message = ScenarioProblem.noName.message; setState {}; return }
        if list.count > 32 { message = ScenarioProblem.tooManyCells.message; setState {}; return }
        cells = list
        let old = editing.flatMap { n in _w.controller.scenarios().first { $0.name == n } }
        valueBoxes = list.map { a in
            let t = TextEditingController()
            t.text = old?.cells.first { $0.ref == a.a1 }?.value ?? _w.controller.scenarioValue(a)
            return t
        }
        page = .values; message = ""; setState {}
    }

    func save() {
        let values = zip(cells, valueBoxes).map { ($0, $1.text) }
        if let p = _w.controller.addScenario(name: name.text, comment: comment.text, values: values, replacing: editing) {
            message = p.message; setState {}; return
        }
        selected = name.text.trimmingWhitespace()
        page = .list; message = ""; setState {}
    }

    func delete() {
        guard let n = selected else { message = "Pick a scenario first."; setState {}; return }
        if let p = _w.controller.deleteScenario(n) { message = p.message } else { selected = nil; message = "" }
        setState {}
    }

    func show() {
        guard let n = selected else { message = "Pick a scenario first."; setState {}; return }
        if let p = _w.controller.showScenario(n) { message = p.message } else { message = ""; _w.controller.onCommand?(.status("Showing scenario \"\(n)\".")) }
        setState {}
    }

    func startSummary() {
        if _w.controller.scenarios().isEmpty { message = "Add a scenario first."; setState {}; return }
        results.text = ""; page = .summary; message = ""; setState {}
    }

    func makeSummary() {
        let (list, bad) = Scenarios.cells(results.text)
        if let bad { message = ScenarioProblem.badCell(bad).message; setState {}; return }
        let out = _w.controller.scenarioSummary(results: list)
        if let p = out.problem { message = p.message; setState {}; return }
        guard out.sheet != nil else { return }
        _w.onClose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        func line(_ label: String, _ id: String, _ c: TextEditingController) -> Widget {
            Row(children: [SizedBox(width: 130, height: nil, child: Text(label)),
                           SizedBox(width: 230, height: Chrome.touchFieldHeight, child: FluentTextBox(key: ValueKey(id), controller: c, placeholderText: ""))])
        }
        let err = Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C)))
        switch page {
        case .list:
            let list = _w.controller.scenarios().filter { !$0.hidden || _w.controller.protection() == nil }
            var rows: [Widget] = [Text("Scenarios:", style: fluent.typography.body), gap(4)]
            if list.isEmpty { rows.append(Text("No scenarios defined. Choose Add to create one.")) }
            for (i, s) in list.enumerated() {
                rows.append(Button(key: ValueKey("scn-item-\(i)"), onPressed: { [weak self] in self?.select(s.name) },
                                   child: Text((selected == s.name ? "▶ " : "   ") + s.name)))
                rows.append(gap(2))
            }
            if let n = selected, let s = list.first(where: { $0.name == n }), !s.comment.isEmpty {
                rows.append(gap(4)); rows.append(Text("Comment: " + s.comment))
            }
            rows.append(gap(8))
            rows.append(Row(children: [
                Button(key: ValueKey("scn-add"), onPressed: { [weak self] in self?.startAdd() }, child: Text("Add…")),
                SizedBox(width: 6, height: nil, child: nil),
                Button(key: ValueKey("scn-edit"), onPressed: { [weak self] in self?.startEdit() }, child: Text("Edit…")),
                SizedBox(width: 6, height: nil, child: nil),
                Button(key: ValueKey("scn-delete"), onPressed: { [weak self] in self?.delete() }, child: Text("Delete")),
                SizedBox(width: 6, height: nil, child: nil),
                Button(key: ValueKey("scn-summary"), onPressed: { [weak self] in self?.startSummary() }, child: Text("Summary…")),
            ]))
            rows.append(gap(6)); rows.append(err)
            return DialogShell(title: "Scenario Manager", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                               okLabel: "Show", cancelLabel: "Close", width: 460,
                               onOK: { [weak self] in self?.show() }, onCancel: _w.onClose)
        case .define:
            let rows: [Widget] = [line("Scenario name:", "scn-name", name), gap(8), line("Changing cells:", "scn-cells", changing), gap(8),
                                  line("Comment:", "scn-comment", comment), gap(6), err]
            return DialogShell(title: editing == nil ? "Add Scenario" : "Edit Scenario", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                               okLabel: "Next", cancelLabel: "Back", width: 420,
                               onOK: { [weak self] in self?.next() }, onCancel: { [weak self] in self?.back() })
        case .values:
            var rows: [Widget] = [Text("Type a value for each changing cell.", style: fluent.typography.body), gap(6)]
            for (i, a) in cells.enumerated() { rows.append(line(a.a1 + ":", "scn-value-\(i)", valueBoxes[i])); rows.append(gap(6)) }
            rows.append(err)
            return DialogShell(title: "Scenario Values", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                               okLabel: "OK", cancelLabel: "Back", width: 420,
                               onOK: { [weak self] in self?.save() }, onCancel: { [weak self] in self?.page = .define; self?.setState {} })
        case .summary:
            let rows: [Widget] = [Text("A new sheet lists every scenario's values side by side.", style: fluent.typography.body), gap(8),
                                  line("Result cells:", "scn-results", results), gap(6), err]
            return DialogShell(title: "Scenario Summary", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
                               okLabel: "OK", cancelLabel: "Back", width: 420,
                               onOK: { [weak self] in self?.makeSummary() }, onCancel: { [weak self] in self?.back() })
        }
    }
}
