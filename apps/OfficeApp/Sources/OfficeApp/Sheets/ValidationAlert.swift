// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-7b: the error alert of a data validation rule as a real dialog, and Circle Invalid Data.
// Stop: Retry / Cancel (the entry is not made). Warning: "Continue?" Yes / No / Cancel.
// Information: OK / Cancel. The alert's title and text come from the rule.

import Flutter
import FlutterSwiftBridge
import Foundation

struct ValidationAlert: Equatable {
    var style: String          // stop, warning, information
    var title: String
    var text: String
}

enum ValidationChoice { case accept, retry, cancel }

extension WorkbookController {
    /// The alert a rule raises for `value` going into `a`, nil when the entry is fine.
    func validationAlert(_ value: CellValue, at a: CellAddress) -> ValidationAlert? {
        guard let rule = validation(at: a), let text = validationRefusal(value, at: a) else { return nil }
        let title = (rule.errorTitle ?? "").isEmpty ? "Microsoft Excel" : rule.errorTitle!
        return ValidationAlert(style: rule.errorStyle, title: title, text: text)
    }

    /// Cells whose value breaks their rule, whether or not the rule shows an alert (Excel circles all).
    func invalidCells() -> [CellAddress] {
        if let c = circleCache, c.edits == edits { return c.cells }
        var out: [CellAddress] = []
        for (a, cell) in sheet.cells where !cell.value.isEmpty && validation(at: a) != nil {
            if validationRefusal(sheet.value(a), at: a, ignoringAlertSetting: true) != nil { out.append(a) }
        }
        out.sort { ($0.row, $0.col) < ($1.row, $1.col) }
        circleCache = (edits, out)
        return out
    }

    func circleInvalidData() -> Int {
        circlesOn = true; circleCache = nil
        let n = invalidCells().count
        _notify()
        return n
    }

    func clearValidationCircles() { circlesOn = false; circleCache = nil; _notify() }
}

final class ValidationAlertDialog: StatefulWidget {
    let alert: ValidationAlert
    let onChoice: (ValidationChoice) -> Void
    init(alert: ValidationAlert, onChoice: @escaping (ValidationChoice) -> Void) {
        self.alert = alert
        self.onChoice = onChoice
        super.init()
    }
    override func createState() -> State<StatefulWidget> { ValidationAlertDialogState() }
}

final class ValidationAlertDialogState: State<StatefulWidget> {
    private var _w: ValidationAlertDialog { widget as! ValidationAlertDialog }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let a = _w.alert
        let say = _w.onChoice
        var lines: [Widget] = [Text(a.text, style: fluent.typography.body)]
        let shell: DialogShell
        switch a.style {
        case "warning":
            lines.append(SizedBox(width: nil, height: 10, child: nil))
            lines.append(Text("Do you want to continue?", style: fluent.typography.body))
            shell = DialogShell(title: a.title, page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: lines),
                                okLabel: "Yes", cancelLabel: "Cancel", width: 420,
                                onOK: { say(.accept) }, onCancel: { say(.cancel) })
            shell.middle = ("No", { say(.retry) })
        case "information":
            shell = DialogShell(title: a.title, page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: lines),
                                okLabel: "OK", cancelLabel: "Cancel", width: 420,
                                onOK: { say(.accept) }, onCancel: { say(.cancel) })
        default:
            shell = DialogShell(title: a.title, page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: lines),
                                okLabel: "Retry", cancelLabel: "Cancel", width: 420,
                                onOK: { say(.retry) }, onCancel: { say(.cancel) })
        }
        return shell
    }
}
