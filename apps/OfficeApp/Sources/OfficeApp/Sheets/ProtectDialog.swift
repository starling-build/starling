// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-6: Review → Protect Sheet / Protect Workbook, and the password prompt that takes them off.
// Protecting a sheet asks what people may still do and, optionally, a password (typed twice);
// removing protection that has a password asks for it.

import Flutter
import FlutterSwiftBridge
import Foundation

final class ProtectDialog: StatefulWidget {
    let controller: WorkbookController
    /// The workbook's structure rather than the active sheet.
    let workbook: Bool
    let onClose: () -> Void

    init(controller: WorkbookController, workbook: Bool, onClose: @escaping () -> Void) {
        self.controller = controller
        self.workbook = workbook
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { ProtectDialogState() }
}

final class ProtectDialogState: State<StatefulWidget> {
    private var _w: ProtectDialog { widget as! ProtectDialog }
    private(set) var allow = SheetProtectionOptions()
    private(set) var message = ""
    private let _password = TextEditingController()
    private let _again = TextEditingController()

    /// Removing protection (true) or setting it (false).
    var removing: Bool { _w.workbook ? _w.controller.book.structureLocked : _w.controller.protection() != nil }

    override func initState() {
        super.initState()
        if let o = _w.controller.sheetProtectionOptions() { allow = o }
    }

    func setAllow(_ key: WritableKeyPath<SheetProtectionOptions, Bool>, _ on: Bool) { setState { allow[keyPath: key] = on } }

    func ok() {
        let c = _w.controller
        if removing {
            let p = _w.workbook ? c.unprotectWorkbook(password: _password.text) : c.unprotectSheet(password: _password.text)
            if let p { message = p.message; setState {}; return }
        } else {
            guard _password.text == _again.text else { message = "The passwords do not match."; setState {}; return }
            if _w.workbook { c.protectWorkbook(password: _password.text) } else { _ = c.protectSheet(allow, password: _password.text) }
        }
        _w.onClose()
    }

    private func _field(_ id: String, _ c: TextEditingController) -> Widget {
        SizedBox(width: nil, height: Chrome.fieldHeight, child: FluentTextBox(
            key: ValueKey(id), controller: c, placeholderText: "", onSubmitted: { [weak self] _ in self?.ok() }, obscureText: true))
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let gap: (Double) -> Widget = { SizedBox(width: nil, height: $0, child: nil) }
        var rows: [Widget] = []
        if removing {
            rows += [Text(_w.workbook ? "Unprotect the workbook structure." : "Unprotect this sheet.", style: fluent.typography.body)]
            if _w.workbook ? _w.controller.workbookHasPassword : _w.controller.sheetHasPassword {
                rows += [gap(8), Text("Password", style: fluent.typography.caption), gap(4), _field("prot-password", _password)]
            }
        } else {
            rows += [Text(_w.workbook ? "Stop sheets being added, removed, renamed, hidden or shown." : "Locked cells cannot be changed.", style: fluent.typography.body),
                     gap(8), Text("Password (optional)", style: fluent.typography.caption), gap(4), _field("prot-password", _password),
                     gap(6), Text("Reenter password", style: fluent.typography.caption), gap(4), _field("prot-again", _again)]
            if !_w.workbook {
                rows += [gap(10), Text("Allow all users of this sheet to:", style: fluent.typography.bodyStrong), gap(4)]
                for k in SheetProtectionOptions.keys {
                    rows.append(Checkbox(key: ValueKey("prot-\(k.attr)"), checked: allow[keyPath: k.path],
                                         onChanged: { [weak self] v in self?.setAllow(k.path, v ?? false) }, content: Text(k.label)))
                    rows.append(gap(2))
                }
            }
        }
        rows += [gap(6), Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C)))]
        return DialogShell(
            title: (removing ? "Unprotect " : "Protect ") + (_w.workbook ? "Workbook" : "Sheet"),
            page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
            okLabel: "OK", cancelLabel: "Cancel", okEnabled: true, width: 380,
            onOK: { [weak self] in self?.ok() }, onCancel: _w.onClose)
    }
}
