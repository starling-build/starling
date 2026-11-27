// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-3b: the Conditional Formatting dialog (Home → Conditional Formatting). Pick
// what to test (a cell value, text, top or bottom, average, duplicates, blanks, a
// formula, a colour scale or a data bar), how matching cells look, and OK adds the
// rule over the selection through the controller's addConditionalFormat (one undo
// step). "Clear rules" takes every rule off the selection. A line above the form
// says how many rules the selection already has.

import Flutter
import FlutterSwiftBridge
import Foundation

final class ConditionalFormatDialog: StatefulWidget {
    let controller: WorkbookController
    let onClose: () -> Void
    /// X-DA-3c Edit Rule: the rule to change (from Manage Rules), shown filled in; nil adds a new rule.
    let editing: CFRuleRow?

    init(controller: WorkbookController, editing: CFRuleRow? = nil, onClose: @escaping () -> Void) {
        self.controller = controller
        self.editing = editing
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { ConditionalFormatDialogState() }
}

final class ConditionalFormatDialogState: State<StatefulWidget> {
    private var _w: ConditionalFormatDialog { widget as! ConditionalFormatDialog }

    static let kinds = ["Cell value", "Text", "Top / bottom", "Above / below average", "Duplicate values",
                        "Blanks", "Errors", "Dates occurring", "Formula", "Color scale", "Data bar", "Icon set"]
    static let periods: [(label: String, value: String)] = [
        ("Yesterday", "yesterday"), ("Today", "today"), ("Tomorrow", "tomorrow"), ("In the last 7 days", "last7Days"),
        ("Last week", "lastWeek"), ("This week", "thisWeek"), ("Next week", "nextWeek"),
        ("Last month", "lastMonth"), ("This month", "thisMonth"), ("Next month", "nextMonth")]
    /// Edit Rule's first look choice: leave the rule's own format as it is.
    static let keepLook = "Keep current format"
    static let iconSets: [(label: String, name: String)] = [
        ("3 arrows", "3Arrows"), ("3 grey arrows", "3ArrowsGray"), ("3 flags", "3Flags"),
        ("3 traffic lights", "3TrafficLights1"), ("3 traffic lights (rimmed)", "3TrafficLights2"),
        ("3 signs", "3Signs"), ("3 symbols (circled)", "3Symbols"), ("3 symbols", "3Symbols2"),
        ("4 arrows", "4Arrows"), ("4 grey arrows", "4ArrowsGray"), ("4 red to black", "4RedToBlack"), ("4 ratings", "4Rating"),
        ("4 traffic lights", "4TrafficLights"), ("5 arrows", "5Arrows"), ("5 grey arrows", "5ArrowsGray"),
        ("5 ratings", "5Rating"), ("5 quarters", "5Quarters"),
        ("3 stars", "3Stars"), ("3 triangles", "3Triangles"), ("5 boxes", "5Boxes")]
    static let opChoices = ValidationDialogState.opChoices
    static let textChoices: [(label: String, op: String)] = [
        ("contains", "containsText"), ("does not contain", "notContainsText"),
        ("begins with", "beginsWith"), ("ends with", "endsWith")]
    static let fills: [(label: String, color: UInt32?)] = [
        ("Light red fill", 0xFFFFC7CE), ("Yellow fill", 0xFFFFEB9C), ("Green fill", 0xFFC6EFCE),
        ("Light blue fill", 0xFFBDD7EE), ("No fill", nil)]
    static let fonts: [(label: String, color: UInt32?)] = [
        ("Dark red text", 0xFF9C0006), ("Dark yellow text", 0xFF9C5700), ("Dark green text", 0xFF006100),
        ("Automatic text", nil)]

    private(set) var kind = "Cell value"
    /// The second choice for the kind: operator, top or bottom, above or below, duplicate or unique, blank or not.
    private(set) var variant = "between"
    private(set) var percent = false
    private(set) var fill = "Light red fill"
    private(set) var font = "Dark red text"
    private(set) var bold = false
    private(set) var message = ""
    private let _v1 = TextEditingController()
    private let _v2 = TextEditingController()
    private let _applies = TextEditingController()
    /// The rule as read for Edit Rule: settings the form has no field for (colours, "or equal" average) come from it.
    private(set) var original: CFRuleEdit?

    override func initState() {
        super.initState()
        guard let row = _w.editing else { return }
        _applies.text = row.applies
        guard let e = _w.controller.conditionalRuleForEdit(row) else { message = CFProblem.notEditable.message; return }
        original = e
        if e.dxfId != nil { fill = Self.keepLook }
        switch e.spec.kind {
        case .cellIs(let op, let a, let b): kind = "Cell value"; variant = op; _v1.text = a; _v2.text = b ?? ""
        case .text(let op, let t): kind = "Text"; variant = op; _v1.text = t
        case .top(let n, let pc, let bottom): kind = "Top / bottom"; variant = bottom ? "bottom" : "top"; _v1.text = "\(n)"; percent = pc
        case .average(let above, _): kind = "Above / below average"; variant = above ? "above" : "below"
        case .duplicates(let unique): kind = "Duplicate values"; variant = unique ? "unique" : "duplicate"
        case .blanks(let yes): kind = "Blanks"; variant = yes ? "blank" : "filled"
        case .errors(let yes): kind = "Errors"; variant = yes ? "errors" : "noErrors"
        case .timePeriod(let p): kind = "Dates occurring"; variant = p
        case .expression(let f): kind = "Formula"; _v1.text = f
        case .colorScale: kind = "Color scale"
        case .dataBar: kind = "Data bar"
        case .iconSet(let name): kind = "Icon set"; variant = name
        }
        if kind == "Icon set", !Self.iconSets.contains(where: { $0.name == variant }) {
            original = nil; kind = "Cell value"; variant = "between"; message = CFProblem.notEditable.message
        }
    }

    override func dispose() {
        _v1.dispose(); _v2.dispose(); _applies.dispose()
        super.dispose()
    }

    /// The variants offered for the current kind, as (label, value).
    var variants: [(label: String, value: String)] {
        switch kind {
        case "Cell value": return Self.opChoices.map { ($0.label, $0.op) }
        case "Text": return Self.textChoices.map { ($0.label, $0.op) }
        case "Top / bottom": return [("Top", "top"), ("Bottom", "bottom")]
        case "Above / below average": return [("Above average", "above"), ("Below average", "below")]
        case "Duplicate values": return [("Duplicate", "duplicate"), ("Unique", "unique")]
        case "Blanks": return [("Blank cells", "blank"), ("Cells with a value", "filled")]
        case "Errors": return [("Cells with errors", "errors"), ("Cells without errors", "noErrors")]
        case "Dates occurring": return Self.periods.map { ($0.label, $0.value) }
        case "Icon set": return Self.iconSets.map { ($0.label, $0.name) }
        default: return []
        }
    }
    var highlights: Bool { kind != "Color scale" && kind != "Data bar" && kind != "Icon set" }

    func setKind(_ k: String) {
        kind = k
        variant = variants.first?.value ?? ""
        message = ""
        setState {}
    }
    func setVariant(_ v: String) { variant = v; setState {} }
    func setFill(_ v: String) { fill = v; setState {} }
    func setFont(_ v: String) { font = v; setState {} }

    func clearRules() {
        let c = _w.controller
        if let p = c.clearConditionalFormats(on: [c.selection]) { message = p.message; setState {} }
        else { _w.onClose() }
    }

    /// OK: build the rule from the form and add it over the selection.
    func apply() {
        let c = _w.controller
        var k: CFSpec.Kind
        switch kind {
        case "Cell value": k = .cellIs(op: variant, _v1.text, variant.hasSuffix("etween") ? _v2.text : nil)
        case "Text": k = .text(op: variant, _v1.text)
        case "Top / bottom":
            guard let n = Int(_v1.text), n > 0 else { message = CFProblem.needsValue.message; setState {}; return }
            k = .top(rank: n, percent: percent, bottom: variant == "bottom")
        case "Above / below average": k = .average(above: variant == "above", equal: false)
        case "Duplicate values": k = .duplicates(unique: variant == "unique")
        case "Blanks": k = .blanks(variant == "blank")
        case "Errors": k = .errors(variant == "errors")
        case "Dates occurring": k = .timePeriod(variant)
        case "Formula": k = .expression(_v1.text)
        case "Color scale":
            if case .colorScale(let cs)? = original?.spec.kind { k = .colorScale(cs) }      // an edited scale keeps its colours
            else { k = .colorScale([0xFFF8696B, 0xFFFFEB84, 0xFF63BE7B]) }
        case "Icon set": k = .iconSet(variant)
        default:
            if case .dataBar(let bar)? = original?.spec.kind { k = .dataBar(bar) } else { k = .dataBar(0xFF638EC6) }
        }
        if case .average(let above, true)? = original?.spec.kind, case .average(let a2, _) = k, a2 == above { k = .average(above: above, equal: true) }
        var spec = CFSpec(kind: k)
        let keep = highlights && fill == Self.keepLook
        if highlights && !keep {
            spec.look.fill = Self.fills.first { $0.label == fill }?.color
            spec.look.color = Self.fonts.first { $0.label == font }?.color
            if bold { spec.look.bold = true }
        }
        let problem: CFProblem?
        if let row = _w.editing {
            guard original != nil else { message = CFProblem.notEditable.message; setState {}; return }
            guard let ranges = WorkbookController.cfRanges(_applies.text) else { message = CFProblem.badRange.message; setState {}; return }
            problem = c.editConditionalRule(row, spec, applies: ranges, keepLook: keep)
        } else {
            problem = c.addConditionalFormat(spec, on: [c.selection])
        }
        if let p = problem { message = p.message; setState {} }
        else { _w.onClose() }
    }

    private func _label(_ s: String, _ fluent: FluentThemeData) -> Widget { Text(s, style: fluent.typography.caption) }
    private func _gap(_ h: Double = 8) -> Widget { SizedBox(width: nil, height: h, child: nil) }
    private func _field(_ id: String, _ c: TextEditingController) -> Widget {
        SizedBox(width: nil, height: Chrome.fieldHeight, child: FluentTextBox(
            key: ValueKey(id), controller: c, placeholderText: "", onSubmitted: { [weak self] _ in self?.apply() }))
    }
    private func _combo(_ id: String, _ value: String, _ items: [(String, String)], _ set: @escaping (String) -> Void) -> Widget {
        SizedBox(width: 240, height: nil, child: ComboBox<String>(
            key: ValueKey(id), value: value,
            items: items.map { ComboBoxItem<String>(value: $0.1, child: Text($0.0)) },
            onChanged: { v in if let v { set(v) } }))
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let existing = _w.controller.conditionalRules(over: _w.controller.selection).count
        let editing = _w.editing != nil
        var rows: [Widget] = editing ? [_label("Applies to", fluent), _field("cf-applies", _applies)] : [
            _label(existing == 0 ? "The selection has no rules yet." : "The selection has \(existing) rule\(existing == 1 ? "" : "s") already.", fluent)]
        rows += [
            _gap(), _label("Format cells based on", fluent),
            _combo("cf-kind", kind, Self.kinds.map { ($0, $0) }) { [weak self] in self?.setKind($0) },
        ]
        if !variants.isEmpty {
            rows += [_gap(), _combo("cf-variant", variant, variants.map { ($0.label, $0.value) }) { [weak self] in self?.setVariant($0) }]
        }
        switch kind {
        case "Cell value":
            rows += [_gap(), _label(variant.hasSuffix("etween") ? "Minimum" : "Value", fluent), _field("cf-value1", _v1)]
            if variant.hasSuffix("etween") { rows += [_gap(), _label("Maximum", fluent), _field("cf-value2", _v2)] }
        case "Text": rows += [_gap(), _label("Text", fluent), _field("cf-value1", _v1)]
        case "Top / bottom":
            rows += [_gap(), _label("How many", fluent), _field("cf-value1", _v1), _gap(6),
                     Checkbox(key: ValueKey("cf-percent"), checked: percent,
                              onChanged: { [weak self] v in self?.setState { self?.percent = v ?? false } }, content: Text("Percent"))]
        case "Formula": rows += [_gap(), _label("Formula (true formats the cell), for the first selected cell", fluent), _field("cf-value1", _v1)]
        default: break
        }
        if highlights {
            // Edit Rule offers the rule's own look first; a look with borders or a number format can only be kept.
            let locked = original?.lookLocked == true
            let fills = (original?.dxfId != nil ? [(Self.keepLook, Self.keepLook)] : []) + (locked ? [] : Self.fills.map { ($0.label, $0.label) })
            rows += [_gap(), _label("Format with", fluent),
                     _combo("cf-fill", fill, fills) { [weak self] in self?.setFill($0) }]
            if fill != Self.keepLook {
                rows += [_gap(6), _combo("cf-font", font, Self.fonts.map { ($0.label, $0.label) }) { [weak self] in self?.setFont($0) }, _gap(6),
                         Checkbox(key: ValueKey("cf-bold"), checked: bold,
                                  onChanged: { [weak self] v in self?.setState { self?.bold = v ?? false } }, content: Text("Bold"))]
            }
        }
        rows += [_gap(), Text(message, style: fluent.typography.caption?.copyWith(color: Color(0xFFC42B1C)))]
        if !editing {
            rows += [_gap(6), Row(children: [Button(key: ValueKey("cf-clear-rules"), onPressed: { [weak self] in self?.clearRules() },
                                                    child: Text("Clear rules"))])]
        }
        return DialogShell(
            title: editing ? "Edit Formatting Rule" : "Conditional Formatting",
            page: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: rows),
            okLabel: "OK", cancelLabel: "Cancel", okEnabled: !editing || original != nil, width: 420,
            onOK: { [weak self] in self?.apply() }, onCancel: _w.onClose)
    }
}
