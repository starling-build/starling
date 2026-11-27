// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-4b: the Data Validation dialog (Data → Data Validation). Three tabs:
// Settings (what to allow, how to compare, the values), Input Message (shown
// under the cell when it is picked) and Error Alert (what happens on a bad
// entry). It opens filled in from the rule on the selected cell. OK puts the
// rule on the selection (one undo step, through the controller's
// setValidation); "Any value" with OK takes validation off the selection, and
// Clear All empties the form to that state.

import Flutter
import FlutterSwiftBridge
import Foundation

final class ValidationDialog: StatefulWidget {
    let controller: WorkbookController
    let onClose: () -> Void

    init(controller: WorkbookController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { ValidationDialogState() }
}

final class ValidationDialogState: State<StatefulWidget> {
    private var _w: ValidationDialog { widget as! ValidationDialog }

    static let allowChoices: [(label: String, type: String)] = [
        ("Any value", "none"), ("Whole number", "whole"), ("Decimal", "decimal"), ("List", "list"),
        ("Date", "date"), ("Time", "time"), ("Text length", "textLength"), ("Custom", "custom"),
    ]
    static let opChoices: [(label: String, op: String)] = [
        ("between", "between"), ("not between", "notBetween"), ("equal to", "equal"), ("not equal to", "notEqual"),
        ("greater than", "greaterThan"), ("less than", "lessThan"),
        ("greater than or equal to", "greaterThanOrEqual"), ("less than or equal to", "lessThanOrEqual"),
    ]
    static let styleChoices: [(label: String, style: String)] = [("Stop", "stop"), ("Warning", "warning"), ("Information", "information")]

    private(set) var allow = "Any value"
    private(set) var op = "between"
    private(set) var ignoreBlank = true
    private(set) var dropdown = true
    private(set) var showError = true
    private(set) var style = "stop"
    private(set) var message = ""
    private let _v1 = TextEditingController()
    private let _v2 = TextEditingController()
    private let _promptTitle = TextEditingController()
    private let _prompt = TextEditingController()
    private let _errTitle = TextEditingController()
    private let _err = TextEditingController()

    var type: String { Self.allowChoices.first { $0.label == allow }?.type ?? "none" }

    override func initState() {
        super.initState()
        let c = _w.controller
        guard let r = c.validationRules(over: c.selection).first else { clearAll(); return }
        allow = Self.allowChoices.first { $0.type == r.type }?.label ?? "Any value"
        op = r.op.isEmpty ? "between" : r.op
        ignoreBlank = r.allowBlank
        dropdown = r.arrow
        showError = r.refuses
        style = r.errorStyle
        _v1.text = Self.shown(r.formula1, list: r.type == "list")
        _v2.text = Self.shown(r.formula2, list: false)
        _promptTitle.text = r.promptTitle ?? ""
        _prompt.text = r.prompt ?? ""
        _errTitle.text = r.errorTitle ?? ""
        _err.text = r.error ?? ""
    }

    override func dispose() {
        for t in [_v1, _v2, _promptTitle, _prompt, _errTitle, _err] { t.dispose() }
        super.dispose()
    }

    /// A stored formula as the user would type it; a typed list shows without its quotes.
    private static func shown(_ f: FormulaExpr?, list: Bool) -> String {
        guard let f else { return "" }
        if list, case .text(let s) = f { return s }
        return Formula.text(f)
    }

    /// Back to "Any value" with the other fields at their defaults.
    func clearAll() {
        allow = "Any value"; op = "between"; ignoreBlank = true; dropdown = true; showError = true; style = "stop"
        message = ""
        for t in [_v1, _v2, _promptTitle, _prompt, _errTitle, _err] { t.text = "" }
        setState {}
    }

    func setAllow(_ label: String) { allow = label; setState {} }
    func setOp(_ value: String) { op = value; setState {} }

    /// OK: validate the form and put the rule on the selection.
    func apply() {
        let c = _w.controller
        if type == "none" {
            c.clearValidation(on: [c.selection])
            _w.onClose()
            return
        }
        var v1 = _v1.text
        if type == "list" {
            var t = v1
            while t.first == " " { t.removeFirst() }
            if t.first != "=" {
                guard let quoted = WorkbookController.listFormulaText([t]) else { message = ValidationProblem.listTooLong.message; setState {}; return }
                v1 = quoted
            }
        }
        let rule = ValidationRule(
            ranges: [c.selection], type: type, op: type == "list" || type == "custom" ? "between" : op,
            formula1: nil, formula2: nil, allowBlank: ignoreBlank, refuses: showError,
            arrow: type == "list" ? dropdown : true,
            errorTitle: _errTitle.text, error: _err.text, errorStyle: style,
            promptTitle: _promptTitle.text, prompt: _prompt.text)
        if let problem = c.setValidation(rule, formula1: v1, formula2: _v2.text) {
            message = problem.message
            setState {}
        } else {
            _w.onClose()
        }
    }

    private func _label(_ s: String, _ fluent: FluentThemeData) -> Widget { Text(s, style: fluent.typography.caption) }
    private func _gap(_ h: Double = 8) -> Widget { SizedBox(width: nil, height: h, child: nil) }
    private func _field(_ id: String, _ c: TextEditingController, placeholder: String = "", height: Double = Chrome.fieldHeight) -> Widget {
        SizedBox(width: nil, height: height, child: FluentTextBox(
            key: ValueKey(id), controller: c, placeholderText: placeholder, onSubmitted: { [weak self] _ in self?.apply() }))
    }
    private func _problem(_ fluent: FluentThemeData) -> Widget {
        Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C)))
    }
    private func _check(_ id: String, _ on: Bool, _ label: String, _ set: @escaping (Bool) -> Void) -> Widget {
        Checkbox(key: ValueKey(id), checked: on, onChanged: { [weak self] v in self?.setState { set(v ?? false) } }, content: Text(label))
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let t = type
        let twoValues = t != "none" && t != "list" && t != "custom" && (op == "between" || op == "notBetween")
        let firstLabel: String = t == "list" ? "Source (items separated by commas, or =range)"
            : t == "custom" ? "Formula" : twoValues ? "Minimum" : "Value"
        var settings: [Widget] = [
            _label("Allow", fluent),
            SizedBox(width: 220, height: nil, child: ComboBox<String>(
                key: ValueKey("validation-allow"), value: allow,
                items: Self.allowChoices.map { ComboBoxItem<String>(value: $0.label, child: Text($0.label)) },
                onChanged: { [weak self] v in if let v { self?.setAllow(v) } })),
        ]
        if t != "none" {
            if t != "list" && t != "custom" {
                settings += [_gap(), _label("Data", fluent),
                    SizedBox(width: 220, height: nil, child: ComboBox<String>(
                        key: ValueKey("validation-op"), value: op,
                        items: Self.opChoices.map { ComboBoxItem<String>(value: $0.op, child: Text($0.label)) },
                        onChanged: { [weak self] v in if let v { self?.setOp(v) } }))]
            }
            settings += [_gap(), _label(firstLabel, fluent), _field("validation-value1", _v1)]
            if twoValues { settings += [_gap(), _label("Maximum", fluent), _field("validation-value2", _v2)] }
            settings += [_gap(), _check("validation-ignore-blank", ignoreBlank, "Ignore blank") { [weak self] in self?.ignoreBlank = $0 }]
            if t == "list" {
                settings += [_check("validation-dropdown", dropdown, "In-cell dropdown") { [weak self] in self?.dropdown = $0 }]
            }
        }
        settings += [_gap(), _problem(fluent), _gap(6),
                     Row(children: [Button(key: ValueKey("validation-clear-all"), onPressed: { [weak self] in self?.clearAll() }, child: Text("Clear All"))])]
        let input = Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: [
            _label("Shown under the cell when it is picked. Leave both empty for no message.", fluent), _gap(),
            _label("Title", fluent), _field("validation-prompt-title", _promptTitle), _gap(),
            _label("Input message", fluent), _field("validation-prompt", _prompt, height: 80),
        ])
        let alert = Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: [
            _check("validation-show-error", showError, "Show an alert after a bad entry") { [weak self] in self?.showError = $0 },
            _gap(), _label("Style", fluent),
            SizedBox(width: 220, height: nil, child: ComboBox<String>(
                key: ValueKey("validation-style"), value: style,
                items: Self.styleChoices.map { ComboBoxItem<String>(value: $0.style, child: Text($0.label)) },
                onChanged: { [weak self] v in if let v { self?.setState { self?.style = v } } })),
            _gap(), _label("Title", fluent), _field("validation-error-title", _errTitle), _gap(),
            _label("Error message", fluent), _field("validation-error", _err, height: 80),
        ])
        return DialogShell(
            title: "Data Validation",
            tabs: [DialogTab(title: "Settings", page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: settings)),
                   DialogTab(title: "Input Message", page: input), DialogTab(title: "Error Alert", page: alert)],
            okLabel: "OK", cancelLabel: "Cancel", okEnabled: true, width: 460,
            onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
