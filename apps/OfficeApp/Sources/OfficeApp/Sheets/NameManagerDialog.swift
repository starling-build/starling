// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CE-3b: the Name Manager. A list of the workbook's defined names, a Name
// field and a "Refers to" field. Pick a name to edit it, or press New to type
// a fresh one; OK applies the fields (add or change), Delete removes the
// picked name. Sheet-local names are listed but read-only (the calculator does
// not scope them yet). Every change is one undo step, made by the controller's
// defineName / editName / deleteName.

import Flutter
import FlutterSwiftBridge
import Foundation

final class NameManagerDialog: StatefulWidget {
    let controller: WorkbookController
    let onClose: () -> Void

    init(controller: WorkbookController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { NameManagerDialogState() }
}

final class NameManagerDialogState: State<StatefulWidget> {
    private var _w: NameManagerDialog { widget as! NameManagerDialog }
    private let _nameField = TextEditingController()
    private let _refersField = TextEditingController()
    /// The entry being edited (its name), or nil while a new name is being typed.
    private(set) var picked: String?
    /// The sheet the picked name is local to, nil for a workbook-wide name.
    private(set) var pickedScope: Int?
    private(set) var message = ""

    override func initState() {
        super.initState()
        startNew()
    }

    override func dispose() {
        _nameField.dispose()
        _refersField.dispose()
        super.dispose()
    }

    private var _entries: [NameEntry] { _w.controller.definedNameEntries() }

    /// Clear the form for a new name; "Refers to" starts as the current selection.
    func startNew() {
        picked = nil
        pickedScope = nil
        message = ""
        _nameField.text = ""
        _refersField.text = _w.controller.selectionReference() ?? ""
        setState {}
    }

    func pick(_ entry: NameEntry) {
        picked = entry.name
        pickedScope = entry.scopeSheet
        message = entry.editable ? "" : "This name is hidden in the file and can't be changed here."
        _nameField.text = entry.name
        _refersField.text = entry.refersTo
        setState {}
    }

    /// OK: define the typed name, or change the picked one. Closes when it worked.
    func apply() {
        let c = _w.controller
        let name = _nameField.text, refers = _refersField.text
        let problem: NameProblem?
        if let old = picked { problem = c.editName(old, to: name, refersTo: refers, scope: pickedScope) }
        else { problem = c.defineName(name, refersTo: refers) }
        if let problem {
            message = problem.message
            setState {}
        } else {
            _w.onClose()
        }
    }

    func deletePicked() {
        guard let old = picked else { return }
        if let problem = _w.controller.deleteName(old, scope: pickedScope) {
            message = problem.message
            setState {}
        } else {
            startNew()
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let entries = _entries
        let rows: [Widget] = entries.map { e in
            let on = e.name == picked && e.scopeSheet == pickedScope
            return KeyboardRow(label: e.name, activate: { [weak self] in self?.pick(e) }, child: GestureDetector(onTap: { [weak self] in self?.pick(e) }, behavior: .opaque, child: ColoredBox(
                color: on ? fluent.resources.subtleFillColorSecondary : Color(0x00000000),
                child: Padding(padding: EdgeInsets(left: 8, top: 4, right: 8, bottom: 4), child: Row(children: [
                    SizedBox(width: 130, height: nil, child: Text(e.name, style: on ? fluent.typography.bodyStrong : fluent.typography.body)),
                    Expanded(child: Text(e.refersTo, style: fluent.typography.caption)),
                    Text(e.scopeSheet.flatMap { $0 < _w.controller.book.sheets.count ? _w.controller.book.sheets[$0].name : nil } ?? (e.scopeSheet == nil ? "Workbook" : "Sheet"), style: fluent.typography.caption),
                ])))))
        }
        let list = SizedBox(width: nil, height: 150, child: SingleChildScrollView(child: Column(
            crossAxisAlignment: .stretch,
            children: rows.isEmpty ? [Padding(padding: EdgeInsets(all: 8), child: Text("No names yet", style: fluent.typography.caption))] : rows)))
        let editable = picked == nil || entries.first { $0.name == picked && $0.scopeSheet == pickedScope }?.editable == true
        let page = Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: [
            list,
            SizedBox(width: nil, height: 10, child: nil),
            Text("Name", style: fluent.typography.caption),
            SizedBox(width: nil, height: 30, child: FluentTextBox(
                key: ValueKey("name-manager-name"), controller: _nameField,
                onSubmitted: { [weak self] _ in self?.apply() }, autofocus: true)),
            SizedBox(width: nil, height: 8, child: nil),
            Text("Refers to", style: fluent.typography.caption),
            SizedBox(width: nil, height: 30, child: FluentTextBox(
                key: ValueKey("name-manager-refers"), controller: _refersField,
                placeholderText: "=Sheet1!$A$1:$B$4",
                onSubmitted: { [weak self] _ in self?.apply() })),
            SizedBox(width: nil, height: 6, child: nil),
            Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C))),
            SizedBox(width: nil, height: 6, child: nil),
            Row(children: [
                Button(onPressed: { [weak self] in self?.startNew() }, child: Text("New")),
                SizedBox(width: 8, height: nil, child: nil),
                Button(onPressed: picked != nil && editable ? { [weak self] in self?.deletePicked() } : nil, child: Text("Delete")),
            ]),
        ])
        return DialogShell(title: "Name Manager", page: page, okLabel: "OK", cancelLabel: "Close", okEnabled: editable, width: 520,
                           onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
